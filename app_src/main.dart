import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xml/xml.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ThuLinhThuApp());
}

class ThuLinhThuApp extends StatelessWidget {
  const ThuLinhThuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thư Linh Thú',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class BookEntry {
  final String id; // unique id
  final String title;
  final String epubPath; // saved epub path in app dir
  const BookEntry({required this.id, required this.title, required this.epubPath});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'epubPath': epubPath};
  static BookEntry fromJson(Map<String, dynamic> j) =>
      BookEntry(id: j['id'], title: j['title'], epubPath: j['epubPath']);
}

class _HomePageState extends State<HomePage> {
  static const _kBooksKey = 'books_v1';

  List<BookEntry> books = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kBooksKey);
    if (raw != null && raw.trim().isNotEmpty) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      books = list.map(BookEntry.fromJson).toList();
    }
    setState(() => loading = false);
  }

  Future<void> _saveBooks() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kBooksKey, jsonEncode(books.map((b) => b.toJson()).toList()));
  }

  Future<void> _pickAndAddEpub() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final pickedPath = result.files.single.path;
    if (pickedPath == null) return;

    final file = File(pickedPath);
    if (!await file.exists()) {
      _toast('Không tìm thấy file.');
      return;
    }

    // Copy epub into app documents to avoid permission issues later
    final docs = await getApplicationDocumentsDirectory();
    final booksDir = Directory(p.join(docs.path, 'books'));
    if (!await booksDir.exists()) await booksDir.create(recursive: true);

    final safeName = p.basename(pickedPath);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final savedPath = p.join(booksDir.path, '$id-$safeName');

    try {
      await file.copy(savedPath);
    } catch (e) {
      _toast('Copy file thất bại: $e');
      return;
    }

    final title = _guessTitleFromFilename(safeName);

    // add / update
    final entry = BookEntry(id: id, title: title, epubPath: savedPath);
    setState(() => books.insert(0, entry));
    await _saveBooks();

    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderPage(book: entry)));
  }

  String _guessTitleFromFilename(String name) {
    var t = name;
    if (t.toLowerCase().endsWith('.epub')) {
      t = t.substring(0, t.length - 5);
    }
    t = t.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    if (t.isEmpty) t = 'Sách EPUB';
    return t;
  }

  Future<void> _removeBook(BookEntry b) async {
    setState(() => books.removeWhere((x) => x.id == b.id));
    await _saveBooks();
    // optional: delete file + extracted folder
    try {
      final f = File(b.epubPath);
      if (await f.exists()) await f.delete();
      final cache = await getTemporaryDirectory();
      final exDir = Directory(p.join(cache.path, 'epub_extracted', b.id));
      if (await exDir.exists()) await exDir.delete(recursive: true);
    } catch (_) {}
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thư Linh Thú'),
        actions: [
          IconButton(
            onPressed: _pickAndAddEpub,
            icon: const Icon(Icons.add),
            tooltip: 'Chọn EPUB',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : books.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book, size: 60),
                        const SizedBox(height: 10),
                        const Text(
                          'Chưa có sách.\nBấm nút + để chọn file .epub từ điện thoại.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _pickAndAddEpub,
                          icon: const Icon(Icons.add),
                          label: const Text('Chọn EPUB'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemBuilder: (_, i) {
                    final b = books[i];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.book)),
                      title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(p.basename(b.epubPath), maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => ReaderPage(book: b))),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeBook(b),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: books.length,
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndAddEpub,
        icon: const Icon(Icons.add),
        label: const Text('Chọn EPUB'),
      ),
    );
  }
}

/// A "strong" EPUB reader:
/// - unzip epub
/// - parse META-INF/container.xml -> .opf
/// - parse .opf manifest + spine
/// - render each spine html/xhtml in WebView (local file)
class ReaderPage extends StatefulWidget {
  final BookEntry book;
  const ReaderPage({super.key, required this.book});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static String _progressKey(String bookId) => 'progress_spine_$bookId';

  bool preparing = true;
  String? errorText;

  late final WebViewController controller;

  // extracted root: .../tmp/epub_extracted/<bookId>/
  late Directory extractedDir;

  // list of absolute file paths to html/xhtml in reading order
  List<_SpineItem> spine = [];
  int spineIndex = 0;

  String bookTitle = '';

  @override
  void initState() {
    super.initState();
    bookTitle = widget.book.title;

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (err) {
            // Some EPUB has missing resources; ignore most, only show if page totally blank.
            // We won't spam errors here.
          },
        ),
      );

    _prepareAndOpen();
  }

  Future<void> _prepareAndOpen() async {
    setState(() {
      preparing = true;
      errorText = null;
    });

    try {
      final cache = await getTemporaryDirectory();
      extractedDir = Directory(p.join(cache.path, 'epub_extracted', widget.book.id));
      if (await extractedDir.exists()) {
        // keep cache (fast open)
      } else {
        await extractedDir.create(recursive: true);
        await _unzipEpub(widget.book.epubPath, extractedDir.path);
      }

      final opfPath = await _findOpfPath(extractedDir);
      final opfFile = File(p.join(extractedDir.path, opfPath));
      if (!await opfFile.exists()) {
        throw Exception('Không tìm thấy content.opf trong EPUB.');
      }

      final opfDirRel = p.dirname(opfPath);
      final opfXml = await opfFile.readAsString();
      final pkg = XmlDocument.parse(opfXml);

      // manifest: id -> href
      final manifest = <String, String>{};
      final manifestItems = pkg.findAllElements('item');
      for (final it in manifestItems) {
        final id = it.getAttribute('id');
        final href = it.getAttribute('href');
        if (id != null && href != null) {
          manifest[id] = href;
        }
      }

      // spine: itemref idref -> manifest href
      final spineItems = <_SpineItem>[];
      final itemrefs = pkg.findAllElements('itemref');
      int idx = 0;
      for (final ir in itemrefs) {
        final idref = ir.getAttribute('idref');
        if (idref == null) continue;
        final href = manifest[idref];
        if (href == null) continue;

        final rel = opfDirRel == '.' ? href : p.join(opfDirRel, href);
        final abs = p.normalize(p.join(extractedDir.path, rel));

        // Only render html/xhtml
        final ext = p.extension(abs).toLowerCase();
        if (ext == '.html' || ext == '.htm' || ext == '.xhtml') {
          idx++;
          spineItems.add(_SpineItem(
            index: idx - 1,
            absPath: abs,
            title: 'Chương ${idx.toString()}',
          ));
        }
      }

      if (spineItems.isEmpty) {
        throw Exception('EPUB này không có spine html/xhtml đọc được.');
      }

      // restore last progress
      final sp = await SharedPreferences.getInstance();
      spineIndex = sp.getInt(_progressKey(widget.book.id)) ?? 0;
      if (spineIndex < 0 || spineIndex >= spineItems.length) spineIndex = 0;

      spine = spineItems;

      await _loadCurrent();

      setState(() => preparing = false);
    } catch (e) {
      setState(() {
        preparing = false;
        errorText = e.toString();
      });
    }
  }

  Future<void> _saveProgress() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_progressKey(widget.book.id), spineIndex);
  }

  Future<void> _loadCurrent() async {
    final item = spine[spineIndex];
    final f = File(item.absPath);

    if (!await f.exists()) {
      // some epub uses different case or broken spine; try to show error
      throw Exception('Thiếu file chương: ${p.basename(item.absPath)}');
    }

    // WebView local file:
    await controller.loadFile(item.absPath);
    await _saveProgress();
    if (mounted) setState(() {});
  }

  Future<void> _next() async {
    if (spineIndex >= spine.length - 1) return;
    setState(() => spineIndex++);
    await _loadCurrent();
  }

  Future<void> _prev() async {
    if (spineIndex <= 0) return;
    setState(() => spineIndex--);
    await _loadCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final currentTitle = (spine.isNotEmpty) ? spine[spineIndex].title : 'Đọc sách';

    return Scaffold(
      appBar: AppBar(
        title: Text(bookTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: Text(bookTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: spine.isEmpty
                    ? null
                    : Text('Chương ${spineIndex + 1}/${spine.length}'),
              ),
              const Divider(height: 1),
              Expanded(
                child: spine.isEmpty
                    ? const SizedBox()
                    : ListView.builder(
                        itemCount: spine.length,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          title: Text(
                            spine[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: i == spineIndex,
                          onTap: () async {
                            Navigator.pop(context);
                            setState(() => spineIndex = i);
                            await _loadCurrent();
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      body: preparing
          ? const Center(child: CircularProgressIndicator())
          : errorText != null
              ? _ErrorView(
                  title: 'Không mở được EPUB',
                  message: errorText!,
                  onRetry: _prepareAndOpen,
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Text(
                        '$currentTitle  •  ${spineIndex + 1}/${spine.length}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(child: WebViewWidget(controller: controller)),
                  ],
                ),
      bottomNavigationBar: (preparing || errorText != null || spine.isEmpty)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: spineIndex == 0 ? null : _prev,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Trước'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: spineIndex == spine.length - 1 ? null : _next,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Sau'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SpineItem {
  final int index;
  final String absPath;
  final String title;
  const _SpineItem({required this.index, required this.absPath, required this.title});
}

class _ErrorView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _unzipEpub(String epubPath, String outDir) async {
  final bytes = await File(epubPath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);

  for (final f in archive) {
    final outPath = p.join(outDir, f.name);

    if (f.isFile) {
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(f.content as List<int>, flush: true);
    } else {
      await Directory(outPath).create(recursive: true);
    }
  }
}

Future<String> _findOpfPath(Directory extractedRoot) async {
  // EPUB standard: META-INF/container.xml -> rootfile full-path="...opf"
  final container = File(p.join(extractedRoot.path, 'META-INF', 'container.xml'));
  if (!await container.exists()) {
    // fallback: find any .opf
    return _fallbackFindOpf(extractedRoot);
  }

  final xmlStr = await container.readAsString();
  final doc = XmlDocument.parse(xmlStr);

  // container.xml uses namespaces sometimes, so find by local name
  final rootfiles = doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'rootfile');
  for (final rf in rootfiles) {
    final fullPath = rf.getAttribute('full-path') ?? rf.getAttribute('fullpath');
    if (fullPath != null && fullPath.toLowerCase().endsWith('.opf')) {
      return fullPath;
    }
  }

  return _fallbackFindOpf(extractedRoot);
}

Future<String> _fallbackFindOpf(Directory extractedRoot) async {
  final files = extractedRoot
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList();

  for (final f in files) {
    if (p.extension(f.path).toLowerCase() == '.opf') {
      // return relative path from extractedRoot
      return p.relative(f.path, from: extractedRoot.path);
    }
  }
  throw Exception('Không tìm thấy file .opf trong EPUB.');
}
