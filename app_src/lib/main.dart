import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LibraryPage(),
    );
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<String> books = [];

  Future<void> loadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => books = prefs.getStringList("books") ?? []);
  }

  Future<void> addBook(String path) async {
    final prefs = await SharedPreferences.getInstance();
    books.remove(path);
    books.insert(0, path);
    await prefs.setStringList("books", books);
    setState(() {});
  }

  Future<void> pickBook() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );
    if (result == null) return;

    final path = result.files.single.path!;
    await addBook(path);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderPage(path: path)),
    );
  }

  @override
  void initState() {
    super.initState();
    loadBooks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tủ sách")),
      floatingActionButton: FloatingActionButton(
        onPressed: pickBook,
        child: const Icon(Icons.add),
      ),
      body: books.isEmpty
          ? const Center(child: Text("Chưa có sách. Bấm + để thêm EPUB."))
          : ListView.builder(
              itemCount: books.length,
              itemBuilder: (_, i) {
                final path = books[i];
                final name = path.split("/").last;
                return ListTile(
                  title: Text(name),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ReaderPage(path: path)),
                    );
                  },
                );
              },
            ),
    );
  }
}

class ReaderPage extends StatefulWidget {
  final String path;
  const ReaderPage({super.key, required this.path});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  List<String> pages = [];
  int pageIndex = 0;
  PageController? controller;

  String bookTitle = "";
  int readSeconds = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _init();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => readSeconds++);
    });
  }

  Future<void> _init() async {
    await _loadProgress();
    await _loadBook();
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("progress:${widget.path}", pageIndex);
  }

  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    pageIndex = prefs.getInt("progress:${widget.path}") ?? 0;
  }

  @override
  void dispose() {
    timer?.cancel();
    controller?.dispose();
    _saveProgress();
    super.dispose();
  }

  // -------- EPUB parsing (no external xml package) --------

  String _attr(String text, String name) {
    final m = RegExp('$name="([^"]+)"', caseSensitive: false).firstMatch(text);
    return m?.group(1) ?? "";
  }

  String _decodeBytes(List<int> data) {
    return utf8.decode(data, allowMalformed: true);
  }

  ArchiveFile? _findFile(Archive zip, String path) {
    // EPUB paths are case-sensitive usually, but some zips differ.
    // Try exact, then case-insensitive fallback.
    for (final f in zip.files) {
      if (!f.isFile) continue;
      if (f.name == path) return f;
    }
    final low = path.toLowerCase();
    for (final f in zip.files) {
      if (!f.isFile) continue;
      if (f.name.toLowerCase() == low) return f;
    }
    return null;
  }

  String _dirOf(String path) {
    final idx = path.lastIndexOf("/");
    if (idx <= 0) return "";
    return path.substring(0, idx + 1);
  }

  String _joinPath(String baseDir, String href) {
    if (href.startsWith("/")) href = href.substring(1);
    // handle ../
    var parts = (baseDir + href).split("/");
    final out = <String>[];
    for (final p in parts) {
      if (p.isEmpty || p == ".") continue;
      if (p == "..") {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(p);
    }
    return out.join("/");
  }

  String _stripHtml(String html) {
    // Basic cleanup: remove scripts/styles + tags.
    var s = html;

    s = s.replaceAll(RegExp(r"(?is)<script[^>]*>.*?</script>"), " ");
    s = s.replaceAll(RegExp(r"(?is)<style[^>]*>.*?</style>"), " ");

    // Keep some line breaks for paragraphs
    s = s.replaceAll(RegExp(r"(?i)</p\s*>"), "\n\n");
    s = s.replaceAll(RegExp(r"(?i)<br\s*/?>"), "\n");

    s = s.replaceAll(RegExp(r"(?is)<[^>]+>"), " ");

    // decode a few common entities
    s = s.replaceAll("&nbsp;", " ");
    s = s.replaceAll("&amp;", "&");
    s = s.replaceAll("&lt;", "<");
    s = s.replaceAll("&gt;", ">");
    s = s.replaceAll("&quot;", '"');
    s = s.replaceAll("&#39;", "'");

    // normalize whitespace
    s = s.replaceAll(RegExp(r"[ \t]+"), " ");
    s = s.replaceAll(RegExp(r"\n{3,}"), "\n\n");
    return s.trim();
  }

  List<String> _paginate(String text, {int pageSize = 1700}) {
    // pageSize is approx characters, but we cut at paragraph/space
    final list = <String>[];
    int start = 0;

    while (start < text.length) {
      int end = min(start + pageSize, text.length);

      if (end < text.length) {
        // Prefer cut at paragraph near end
        int best = -1;
        final para = text.lastIndexOf("\n\n", end);
        if (para > start + 200) best = para + 2;

        if (best == -1) {
          // Else cut at space
          int cut = end;
          while (cut > start && text[cut - 1] != " ") {
            cut--;
          }
          if (cut > start + 200) best = cut;
        }

        if (best != -1) end = best;
      }

      final page = text.substring(start, end).trim();
      if (page.isNotEmpty) list.add(page);

      start = end;
    }

    return list.isEmpty ? [""] : list;
  }

  Future<void> _loadBook() async {
    final bytes = await File(widget.path).readAsBytes();
    final zip = ZipDecoder().decodeBytes(bytes);

    // 1) Find OPF from META-INF/container.xml
    String opfPath = "";
    final containerFile = _findFile(zip, "META-INF/container.xml");
    if (containerFile != null) {
      final xml = _decodeBytes(containerFile.content as List<int>);
      final m = RegExp(r'full-path="([^"]+)"', caseSensitive: false).firstMatch(xml);
      opfPath = m?.group(1) ?? "";
    }

    // 2) If no OPF found, fallback later
    List<String> orderedHtmlPaths = [];
    String title = "";

    if (opfPath.isNotEmpty) {
      final opfFile = _findFile(zip, opfPath);
      if (opfFile != null) {
        final opf = _decodeBytes(opfFile.content as List<int>);
        final baseDir = _dirOf(opfPath);

        // title
        final t = RegExp(r"(?is)<dc:title[^>]*>(.*?)</dc:title>").firstMatch(opf)?.group(1);
        if (t != null) title = _stripHtml(t);

        // manifest id->href
        final manifest = <String, String>{};
        for (final m in RegExp(r"(?is)<item\b[^>]*>").allMatches(opf)) {
          final tag = m.group(0)!;
          final id = _attr(tag, "id");
          final href = _attr(tag, "href");
          final media = _attr(tag, "media-type").toLowerCase();
          if (id.isEmpty || href.isEmpty) continue;

          final isHtml = media.contains("application/xhtml+xml") || media.contains("text/html");
          if (isHtml) {
            manifest[id] = _joinPath(baseDir, href);
          }
        }

        // spine order
        final spine = <String>[];
        for (final m in RegExp(r'(?is)<itemref\b[^>]*idref="([^"]+)"[^>]*>').allMatches(opf)) {
          spine.add(m.group(1)!);
        }

        for (final idref in spine) {
          final p = manifest[idref];
          if (p != null) orderedHtmlPaths.add(p);
        }
      }
    }

    // Fallback: just collect all html/xhtml and sort
    if (orderedHtmlPaths.isEmpty) {
      final all = <String>[];
      for (final f in zip.files) {
        if (!f.isFile) continue;
        final n = f.name.toLowerCase();
        if (n.endsWith(".html") || n.endsWith(".xhtml")) all.add(f.name);
      }
      all.sort();
      orderedHtmlPaths = all;
    }

    // Read in order and build text
    final buf = StringBuffer();
    for (final p in orderedHtmlPaths) {
      final f = _findFile(zip, p);
      if (f == null) continue;
      final html = _decodeBytes(f.content as List<int>);
      final plain = _stripHtml(html);
      if (plain.isEmpty) continue;
      buf.writeln(plain);
      buf.writeln("\n");
    }

    final fullText = buf.toString().trim();
    final newPages = _paginate(fullText, pageSize: 1700);

    // Important: clamp() returns num => convert to int
    final int safeIndex = (pageIndex.clamp(0, newPages.length - 1) as num).toInt();

    controller?.dispose();
    controller = PageController(initialPage: safeIndex);

    setState(() {
      bookTitle = title.isNotEmpty ? title : widget.path.split("/").last;
      pages = newPages;
      pageIndex = safeIndex;
    });
  }

  String _formatTime(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return "${h}h ${m}m ${sec}s";
    return "${m}m ${sec}s";
  }

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty || controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(bookTitle, overflow: TextOverflow.ellipsis),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: pages.length,
            onPageChanged: (i) {
              pageIndex = i;
              _saveProgress();
            },
            itemBuilder: (_, i) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                  child: Text(
                    pages[i],
                    style: const TextStyle(fontSize: 18, height: 1.65),
                  ),
                ),
              );
            },
          ),

          // Time overlay (moved to TOP-LEFT, smaller, less blocking)
          Positioned(
            left: 8,
            top: 8,
            child: Opacity(
              opacity: 0.75,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _formatTime(readSeconds),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
