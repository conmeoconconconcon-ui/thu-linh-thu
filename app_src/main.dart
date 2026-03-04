import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ThuLinhThuApp());
}

class ThuLinhThuApp extends StatelessWidget {
  const ThuLinhThuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thu Linh Thu',
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
  static const _kLastEpubPath = 'last_epub_path';

  bool _loading = false;
  String? _error;

  EpubBook? _book;
  int _chapterIndex = 0;

  InAppWebViewController? _web;

  @override
  void initState() {
    super.initState();
    _autoOpenLast();
  }

  Future<void> _autoOpenLast() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_kLastEpubPath);
    if (last != null && last.isNotEmpty && File(last).existsSync()) {
      unawaited(_openEpub(File(last)));
    }
  }

  Future<void> _pickEpub() async {
    setState(() {
      _error = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    await _openEpub(File(path));
  }

  Future<void> _openEpub(File source) async {
    setState(() {
      _loading = true;
      _error = null;
      _book = null;
      _chapterIndex = 0;
    });

    try {
      // Copy vào sandbox app để khỏi bị quyền file/uri lằng nhằng
      final docs = await getApplicationDocumentsDirectory();
      final safeDir = Directory(p.join(docs.path, 'library'));
      if (!safeDir.existsSync()) safeDir.createSync(recursive: true);

      final safePath = p.join(
        safeDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(source.path)}',
      );
      final safeFile = await source.copy(safePath);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastEpubPath, safeFile.path);

      final book = await EpubEngine.extractAndParse(safeFile);

      setState(() {
        _book = book;
        _chapterIndex = 0;
      });

      await _loadChapter(0);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadChapter(int index) async {
    final book = _book;
    if (book == null) return;
    if (index < 0 || index >= book.chapters.length) return;

    setState(() {
      _chapterIndex = index;
      _error = null;
    });

    final chapterFile = File(book.chapters[index].absolutePath);

    if (!chapterFile.existsSync()) {
      setState(() {
        _error = 'Không tìm thấy chương: ${chapterFile.path}';
      });
      return;
    }

    // Load file trực tiếp để ảnh/css link tương đối chạy ngon
    await _web?.loadFile(
      assetFilePath: chapterFile.path,
    );
  }

  Future<void> _prev() async {
    if (_book == null) return;
    if (_chapterIndex <= 0) return;
    await _loadChapter(_chapterIndex - 1);
  }

  Future<void> _next() async {
    final book = _book;
    if (book == null) return;
    if (_chapterIndex >= book.chapters.length - 1) return;
    await _loadChapter(_chapterIndex + 1);
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;

    return Scaffold(
      appBar: AppBar(
        title: Text(book?.title ?? 'Thu Linh Thu'),
        actions: [
          IconButton(
            onPressed: _pickEpub,
            icon: const Icon(Icons.folder_open),
            tooltip: 'Chọn EPUB',
          ),
          if (book != null)
            IconButton(
              onPressed: () async {
                final cover = book.coverImagePath;
                if (cover == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('EPUB này không có cover (hoặc không khai báo chuẩn).')),
                  );
                  return;
                }
                await showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    child: Image.file(File(cover), fit: BoxFit.contain),
                  ),
                );
              },
              icon: const Icon(Icons.image),
              tooltip: 'Xem bìa',
            ),
        ],
      ),
      drawer: book == null
          ? null
          : Drawer(
              child: ListView(
                children: [
                  DrawerHeader(
                    child: Text(
                      book.title ?? 'Mục lục',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (int i = 0; i < book.chapters.length; i++)
                    ListTile(
                      title: Text(book.chapters[i].title ?? 'Chương ${i + 1}'),
                      selected: i == _chapterIndex,
                      onTap: () async {
                        Navigator.pop(context);
                        await _loadChapter(i);
                      },
                    ),
                ],
              ),
            ),
      body: Column(
        children: [
          if (_loading)
            const LinearProgressIndicator(minHeight: 3),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.withOpacity(0.08),
              child: Text(
                'Không mở được EPUB:\n$_error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialSettings: InAppWebViewSettings(
                // Cho phép file:// load ảnh/css
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
                allowFileAccess: true,
                javaScriptEnabled: true,
                supportZoom: true,
                builtInZoomControls: true,
                displayZoomControls: false,
                // Đỡ bị chặn mixed-content nếu EPUB có link http
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              ),
              onWebViewCreated: (c) {
                _web = c;
              },
              shouldOverrideUrlLoading: (controller, nav) async {
                // Link nội bộ trong EPUB (anchor, file) -> cho chạy bình thường
                return NavigationActionPolicy.ALLOW;
              },
              onLoadError: (controller, url, code, message) {
                setState(() {
                  _error = 'WebView load lỗi ($code): $message';
                });
              },
            ),
          ),
          if (book != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _prev,
                        child: const Text('Trang trước'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _next,
                        child: const Text('Trang sau'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/* =======================
   EPUB ENGINE (tolerant)
   ======================= */

class EpubBook {
  final String? title;
  final String extractedRoot; // thư mục giải nén
  final String? coverImagePath;
  final List<EpubChapter> chapters;

  EpubBook({
    required this.title,
    required this.extractedRoot,
    required this.coverImagePath,
    required this.chapters,
  });
}

class EpubChapter {
  final String? title;
  final String absolutePath;

  EpubChapter({required this.title, required this.absolutePath});
}

class EpubEngine {
  static Future<EpubBook> extractAndParse(File epubFile) async {
    final cache = await getTemporaryDirectory();
    final outDir = Directory(p.join(
      cache.path,
      'epub_extracted',
      DateTime.now().millisecondsSinceEpoch.toString(),
    ));
    outDir.createSync(recursive: true);

    final bytes = await epubFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);

    // Extract all files
    for (final f in archive) {
      final filename = f.name;
      final outPath = p.join(outDir.path, filename);

      if (f.isFile) {
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        final data = f.content as List<int>;
        await outFile.writeAsBytes(data, flush: true);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }

    // 1) Tìm container.xml (case-insensitive)
    final containerPath = await _findFileCaseInsensitive(outDir, p.join('META-INF', 'container.xml'))
        ?? await _findAnyByName(outDir, 'container.xml');

    String? opfRelPath;
    if (containerPath != null && File(containerPath).existsSync()) {
      opfRelPath = await _parseContainerForOpf(containerPath);
    }

    // 2) Nếu container.xml fail -> scan *.opf (fallback)
    opfRelPath ??= await _scanForAnyOpf(outDir);

    if (opfRelPath == null) {
      // 3) EPUB quá bẩn: fallback scan html/xhtml rồi đọc kiểu “thư mục”
      final chapters = await _fallbackScanHtml(outDir);
      if (chapters.isEmpty) {
        throw Exception('EPUB không có .opf và cũng không tìm thấy file html/xhtml để đọc.');
      }
      return EpubBook(
        title: p.basenameWithoutExtension(epubFile.path),
        extractedRoot: outDir.path,
        coverImagePath: null,
        chapters: chapters,
      );
    }

    final opfAbs = p.isAbsolute(opfRelPath) ? opfRelPath : p.join(outDir.path, opfRelPath);
    if (!File(opfAbs).existsSync()) {
      throw Exception('Tìm thấy đường dẫn OPF nhưng file không tồn tại: $opfRelPath');
    }

    final opfXml = await File(opfAbs).readAsString();
    final opfDoc = XmlDocument.parse(opfXml);

    final metadataTitle = _readFirstText(opfDoc, ['dc:title', 'title']);
    final title = (metadataTitle?.trim().isNotEmpty ?? false)
        ? metadataTitle!.trim()
        : p.basenameWithoutExtension(epubFile.path);

    // Root folder để resolve href tương đối
    final opfDirAbs = p.dirname(opfAbs);

    // manifest: id -> href
    final manifestItems = <String, Map<String, String>>{};
    for (final item in opfDoc.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      final media = item.getAttribute('media-type');
      final props = item.getAttribute('properties') ?? '';
      if (id != null && href != null) {
        manifestItems[id] = {
          'href': href,
          'media': media ?? '',
          'props': props,
        };
      }
    }

    // cover (tolerant)
    String? coverPathAbs = _tryFindCover(opfDoc, manifestItems, opfDirAbs);
    if (coverPathAbs != null && !File(coverPathAbs).existsSync()) {
      coverPathAbs = null;
    }

    // spine: list itemref -> manifest href
    final chapters = <EpubChapter>[];
    int idx = 0;
    for (final itemref in opfDoc.findAllElements('itemref')) {
      final idref = itemref.getAttribute('idref');
      if (idref == null) continue;
      final mi = manifestItems[idref];
      if (mi == null) continue;

      final href = mi['href']!;
      final abs = p.normalize(p.join(opfDirAbs, href));

      // Chỉ lấy html/xhtml
      final lower = abs.toLowerCase();
      if (!(lower.endsWith('.xhtml') || lower.endsWith('.html') || lower.endsWith('.htm'))) continue;

      idx++;
      chapters.add(EpubChapter(
        title: 'Chương $idx',
        absolutePath: abs,
      ));
    }

    // Nếu spine rỗng -> fallback scan html
    if (chapters.isEmpty) {
      final fallback = await _fallbackScanHtml(outDir);
      if (fallback.isNotEmpty) {
        return EpubBook(
          title: title,
          extractedRoot: outDir.path,
          coverImagePath: coverPathAbs,
          chapters: fallback,
        );
      }
      throw Exception('OPF có nhưng spine không ra chương html/xhtml.');
    }

    return EpubBook(
      title: title,
      extractedRoot: outDir.path,
      coverImagePath: coverPathAbs,
      chapters: chapters,
    );
  }

  static Future<String?> _parseContainerForOpf(String containerAbsPath) async {
    final xmlStr = await File(containerAbsPath).readAsString();
    final doc = XmlDocument.parse(xmlStr);
    // container.xml: rootfiles/rootfile full-path="..."
    final rootfile = doc.findAllElements('rootfile').firstOrNull;
    final fullPath = rootfile?.getAttribute('full-path');
    return fullPath;
  }

  static String? _tryFindCover(
    XmlDocument opfDoc,
    Map<String, Map<String, String>> manifest,
    String opfDirAbs,
  ) {
    // Cách 1: item properties="cover-image"
    for (final entry in manifest.entries) {
      final props = (entry.value['props'] ?? '').toLowerCase();
      final href = entry.value['href'] ?? '';
      if (props.contains('cover-image') && href.isNotEmpty) {
        return p.normalize(p.join(opfDirAbs, href));
      }
    }

    // Cách 2: <meta name="cover" content="cover-id" />
    for (final meta in opfDoc.findAllElements('meta')) {
      final name = (meta.getAttribute('name') ?? '').toLowerCase();
      if (name == 'cover') {
        final coverId = meta.getAttribute('content');
        if (coverId != null && manifest[coverId]?['href'] != null) {
          return p.normalize(p.join(opfDirAbs, manifest[coverId]!['href']!));
        }
      }
    }

    // Cách 3: đoán theo file name
    for (final entry in manifest.entries) {
      final href = (entry.value['href'] ?? '').toLowerCase();
      if (href.contains('cover') && (href.endsWith('.jpg') || href.endsWith('.jpeg') || href.endsWith('.png') || href.endsWith('.webp'))) {
        return p.normalize(p.join(opfDirAbs, entry.value['href']!));
      }
    }
    return null;
  }

  static Future<String?> _scanForAnyOpf(Directory root) async {
    final files = root
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .toList();
    for (final f in files) {
      if (f.path.toLowerCase().endsWith('.opf')) {
        return p.relative(f.path, from: root.path);
      }
    }
    return null;
  }

  static Future<List<EpubChapter>> _fallbackScanHtml(Directory root) async {
    final files = root
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) {
          final l = f.path.toLowerCase();
          return l.endsWith('.xhtml') || l.endsWith('.html') || l.endsWith('.htm');
        })
        .toList();

    files.sort((a, b) => a.path.compareTo(b.path));

    int i = 0;
    return files.map((f) {
      i++;
      return EpubChapter(title: 'Trang $i', absolutePath: f.path);
    }).toList();
  }

  static Future<String?> _findFileCaseInsensitive(Directory root, String relPath) async {
    // relPath kiểu META-INF/container.xml
    final parts = p.split(relPath);
    Directory current = root;
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      final entries = current.listSync(followLinks: false);

      final match = entries.firstWhere(
        (e) => p.basename(e.path).toLowerCase() == part.toLowerCase(),
        orElse: () => Directory(''),
      );

      if (match.path.isEmpty) return null;

      if (i == parts.length - 1) {
        return match.path;
      }

      if (match is Directory) {
        current = match;
      } else {
        return null;
      }
    }
    return null;
  }

  static Future<String?> _findAnyByName(Directory root, String filename) async {
    final files = root.listSync(recursive: true, followLinks: false);
    for (final e in files) {
      if (p.basename(e.path).toLowerCase() == filename.toLowerCase()) {
        return e.path;
      }
    }
    return null;
  }

  static String? _readFirstText(XmlDocument doc, List<String> possibleNames) {
    for (final name in possibleNames) {
      final el = doc.findAllElements(name).firstOrNull;
      if (el != null) return el.text;
    }
    return null;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
