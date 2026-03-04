import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:xml/xml.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Đọc EPUB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool loading = false;
  String? error;
  String title = "Đọc sách";

  List<_HtmlPage> pages = [];
  int pageIndex = 0;

  Future<void> pickAndOpenEpub() async {
    setState(() {
      loading = true;
      error = null;
      pages = [];
      pageIndex = 0;
      title = "Đọc sách";
    });

    try {
      // QUAN TRỌNG: withData=true để Android trả bytes ổn định (tránh lỗi mở file)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['epub'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => loading = false);
        return;
      }

      final Uint8List? bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Không đọc được dữ liệu file (bytes null). Hãy chọn lại file.');
      }

      final zip = ZipDecoder().decodeBytes(bytes, verify: false);

      // 1) Thử đọc chuẩn OPF/spine
      final parsed = _tryParseStandard(zip);

      if (parsed.pages.isNotEmpty) {
        setState(() {
          title = parsed.title ?? "Unknown";
          pages = parsed.pages;
          loading = false;
        });
        return;
      }

      // 2) Fallback mạnh: quét tất cả html/xhtml trong zip
      final fallbackPages = _fallbackScanAllHtml(zip);

      if (fallbackPages.isEmpty) {
        throw Exception("Không tìm thấy nội dung HTML/XHTML trong EPUB.");
      }

      setState(() {
        title = parsed.title ?? "Unknown";
        pages = fallbackPages;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRead = pages.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: loading ? null : pickAndOpenEpub,
            icon: const Icon(Icons.folder_open),
            tooltip: "Chọn EPUB",
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _ErrorView(message: error!, onRetry: pickAndOpenEpub)
              : !canRead
                  ? Center(
                      child: ElevatedButton.icon(
                        onPressed: pickAndOpenEpub,
                        icon: const Icon(Icons.folder_open),
                        label: const Text("Chọn EPUB để đọc"),
                      ),
                    )
                  : _ReaderView(
                      pages: pages,
                      pageIndex: pageIndex,
                      onPrev: pageIndex > 0 ? () => setState(() => pageIndex--) : null,
                      onNext: pageIndex < pages.length - 1 ? () => setState(() => pageIndex++) : null,
                    ),
    );
  }
}

class _ReaderView extends StatelessWidget {
  final List<_HtmlPage> pages;
  final int pageIndex;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _ReaderView({
    required this.pages,
    required this.pageIndex,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final page = pages[pageIndex];

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            "${pageIndex + 1}/${pages.length}  •  ${page.name}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Html(
              data: page.html,
              // Cố tình bỏ ảnh để khỏi lỗi path
              extensions: const [],
              style: {
                "body": Style(
                  fontSize: FontSize(18),
                  lineHeight: const LineHeight(1.6),
                ),
              },
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: onPrev,
                    child: const Text("Trang trước"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onNext,
                    child: const Text("Trang sau"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            const Text("Không mở được EPUB", style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text("Thử lại"),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParsedEpub {
  final String? title;
  final List<_HtmlPage> pages;
  _ParsedEpub({required this.title, required this.pages});
}

class _HtmlPage {
  final String name;
  final String html;
  _HtmlPage(this.name, this.html);
}

/// 1) đọc chuẩn OPF/spine (nếu EPUB chuẩn)
_ParsedEpub _tryParseStandard(Archive zip) {
  String? title;
  final pages = <_HtmlPage>[];

  final containerPath = _findFilePath(zip, (p) => p.toLowerCase() == 'meta-inf/container.xml');
  if (containerPath == null) return _ParsedEpub(title: null, pages: []);

  final containerXml = _readText(zip, containerPath);
  if (containerXml == null) return _ParsedEpub(title: null, pages: []);

  String? opfPath;
  try {
    final doc = XmlDocument.parse(containerXml);
    for (final r in doc.findAllElements('rootfile')) {
      final fp = r.getAttribute('full-path');
      if (fp != null && fp.trim().isNotEmpty && !fp.trim().endsWith('/')) {
        opfPath = fp.trim();
        break;
      }
    }
  } catch (_) {
    return _ParsedEpub(title: null, pages: []);
  }
  if (opfPath == null) return _ParsedEpub(title: null, pages: []);

  final opfText = _readText(zip, opfPath);
  if (opfText == null) return _ParsedEpub(title: null, pages: []);

  final opfDir = _dirOf(opfPath);

  try {
    final opf = XmlDocument.parse(opfText);

    final titles = opf.findAllElements('dc:title');
    if (titles.isNotEmpty) title = titles.first.innerText.trim();

    final manifest = <String, String>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) manifest[id] = href;
    }

    final spineIds = <String>[];
    for (final itemref in opf.findAllElements('itemref')) {
      final idref = itemref.getAttribute('idref');
      if (idref != null) spineIds.add(idref);
    }

    for (final id in spineIds) {
      final href = manifest[id];
      if (href == null) continue;

      final path = _joinPath(opfDir, href);
      final html = _readText(zip, path);
      if (html == null) continue;

      pages.add(_HtmlPage(path, _stripImages(html)));
    }
  } catch (_) {
    return _ParsedEpub(title: null, pages: []);
  }

  return _ParsedEpub(title: title, pages: pages);
}

/// 2) fallback “cứng”: quét toàn zip, đọc tất cả html/xhtml
List<_HtmlPage> _fallbackScanAllHtml(Archive zip) {
  final htmlFiles = <String>[];

  for (final f in zip.files) {
    if (!f.isFile) continue;
    final p = f.name;
    final low = p.toLowerCase();
    if (low.endsWith('.html') || low.endsWith('.htm') || low.endsWith('.xhtml')) {
      htmlFiles.add(p);
    }
  }
  if (htmlFiles.isEmpty) return [];

  htmlFiles.sort((a, b) => _scorePath(b).compareTo(_scorePath(a)));

  final pages = <_HtmlPage>[];
  for (final path in htmlFiles) {
    final html = _readText(zip, path);
    if (html == null) continue;

    final cleaned = _stripImages(html).replaceAll('\u0000', '');
    if (cleaned.trim().length < 40) continue;

    pages.add(_HtmlPage(path, cleaned));
  }
  return pages;
}

int _scorePath(String path) {
  final p = path.toLowerCase();
  int score = 0;

  if (p.contains('oebps')) score += 30;
  if (p.contains('ops')) score += 25;
  if (p.contains('/text/')) score += 25;
  if (p.contains('chapter') || p.contains('chap') || p.contains('split')) score += 20;
  if (RegExp(r'(\d{1,4})').hasMatch(p)) score += 15;
  if (p.contains('toc') || p.contains('nav')) score -= 30;
  if (p.contains('cover')) score -= 10;

  score += (p.split('/').length - 1);
  return score;
}

String _stripImages(String html) {
  // Bỏ <img ...> để khỏi vướng path ảnh
  return html.replaceAll(RegExp(r'<img\b[^>]*>', caseSensitive: false), '');
}

String? _findFilePath(Archive zip, bool Function(String path) test) {
  for (final f in zip.files) {
    final n = f.name;
    if (test(n)) return n;
  }
  return null;
}

String? _readText(Archive zip, String path) {
  final file = zip.files.firstWhere(
    (f) => f.name == path,
    orElse: () => ArchiveFile('', 0, []),
  );
  if (file.name.isEmpty || !file.isFile) return null;

  final data = file.content;
  if (data is List<int>) {
    try {
      return utf8.decode(data, allowMalformed: true);
    } catch (_) {
      return latin1.decode(data, allowInvalid: true);
    }
  }
  return null;
}

String _dirOf(String pth) {
  final i = pth.lastIndexOf('/');
  if (i <= 0) return '';
  return pth.substring(0, i);
}

String _joinPath(String base, String rel) {
  if (base.isEmpty) return rel;
  if (rel.startsWith('/')) return rel.substring(1);
  return "$base/$rel";
}
