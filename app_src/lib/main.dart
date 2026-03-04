import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "EPUB Reader",
      theme: ThemeData.dark(useMaterial3: true),
      home: const LibraryPage(),
    );
  }
}

/// =======================
/// Helpers: ngày & format giờ đọc
/// =======================
String dayKey(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return "$y-$m-$d";
}

String formatHms(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return "${h}h${m.toString().padLeft(2, '0')}m";
  return "${m}m${s.toString().padLeft(2, '0')}s";
}

/// =======================
/// Store: thời gian đọc hôm nay
/// =======================
class ReadingTimeStore {
  static const _kDay = "read_day_key_v1";
  static const _kSec = "read_seconds_today_v1";

  static Future<int> loadSecondsToday() async {
    final sp = await SharedPreferences.getInstance();
    final today = dayKey(DateTime.now());
    final savedDay = sp.getString(_kDay);
    if (savedDay != today) {
      await sp.setString(_kDay, today);
      await sp.setInt(_kSec, 0);
      return 0;
    }
    return sp.getInt(_kSec) ?? 0;
  }

  static Future<void> saveSecondsToday(int seconds) async {
    final sp = await SharedPreferences.getInstance();
    final today = dayKey(DateTime.now());
    final savedDay = sp.getString(_kDay);
    if (savedDay != today) {
      await sp.setString(_kDay, today);
      seconds = 0;
    }
    await sp.setInt(_kSec, seconds);
  }
}

/// =======================
/// Library: sách đã mở (tự lưu)
/// =======================
class BookItem {
  final String path;
  final String title;
  final int lastPage;
  final double progress;

  BookItem({
    required this.path,
    required this.title,
    this.lastPage = 0,
    this.progress = 0.0,
  });

  BookItem copyWith({int? lastPage, double? progress}) => BookItem(
        path: path,
        title: title,
        lastPage: lastPage ?? this.lastPage,
        progress: progress ?? this.progress,
      );

  Map<String, dynamic> toMap() => {
        "path": path,
        "title": title,
        "lastPage": lastPage,
        "progress": progress,
      };

  factory BookItem.fromMap(Map<String, dynamic> map) => BookItem(
        path: map["path"],
        title: map["title"],
        lastPage: map["lastPage"] ?? 0,
        progress: ((map["progress"] ?? 0.0) as num).toDouble(),
      );
}

class LibraryStore {
  static const _k = "library_simple_v1";

  static Future<List<BookItem>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(BookItem.fromMap).toList();
  }

  static Future<void> save(List<BookItem> books) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k, jsonEncode(books.map((b) => b.toMap()).toList()));
  }
}

/// =======================
/// EPUB -> TEXT pages (chỉ chữ)
/// =======================
String htmlToPlainText(String html) {
  var s = html;
  s = s.replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n');
  s = s.replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</h[1-6]\s*>', caseSensitive: false), '\n\n');
  s = s.replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');

  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  s = s
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return s;
}

List<String> paginateText(String text, {int maxCharsPerPage = 1800}) {
  final paras = text.split(RegExp(r'\n\s*\n'));
  final pages = <String>[];

  final buf = StringBuffer();
  int len = 0;

  void flush() {
    final t = buf.toString().trim();
    if (t.isNotEmpty) pages.add(t);
    buf.clear();
    len = 0;
  }

  for (final p0 in paras) {
    final para = p0.trim();
    if (para.isEmpty) continue;

    if (para.length > maxCharsPerPage) {
      if (len > 0) flush();
      int start = 0;
      while (start < para.length) {
        final end = min(start + maxCharsPerPage, para.length);
        pages.add(para.substring(start, end).trim());
        start = end;
      }
      continue;
    }

    final addLen = para.length + 2;
    if (len + addLen > maxCharsPerPage) flush();

    buf.writeln(para);
    buf.writeln();
    len += addLen;
  }

  if (len > 0) flush();
  return pages.isEmpty ? ["(Không có nội dung)"] : pages;
}

Future<List<String>> epubToTextPages(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final zip = ZipDecoder().decodeBytes(bytes, verify: false);

  final htmlList = <String>[];
  for (final f in zip.files) {
    if (!f.isFile) continue;
    final low = f.name.toLowerCase();
    if (low.endsWith(".xhtml") || low.endsWith(".html") || low.endsWith(".htm")) {
      final data = f.content as List<int>;
      htmlList.add(utf8.decode(data, allowMalformed: true));
    }
  }

  if (htmlList.isEmpty) return ["(EPUB không có HTML/XHTML)"];
  final fullText = htmlList.map(htmlToPlainText).join("\n\n");
  return paginateText(fullText, maxCharsPerPage: 1800);
}

/// =======================
/// UI: TỦ SÁCH
/// =======================
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<BookItem> books = [];

  @override
  void initState() {
    super.initState();
    LibraryStore.load().then((b) {
      if (!mounted) return;
      setState(() => books = b);
    });
  }

  Future<void> pickAndOpen() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ["epub"],
      withData: false,
    );
    if (res == null || res.files.isEmpty) return;

    final path = res.files.first.path;
    if (path == null) return;

    final title = pBasenameWithoutExt(res.files.first.name);

    // nếu chưa có trong tủ sách thì thêm
    final idx = books.indexWhere((b) => b.path == path);
    if (idx < 0) {
      books = [BookItem(path: path, title: title), ...books];
      await LibraryStore.save(books);
      if (mounted) setState(() {});
    }

    // mở đọc
    final opened = books.firstWhere((b) => b.path == path);
    final result = await Navigator.push<BookItem>(
      context,
      MaterialPageRoute(builder: (_) => ReaderPage(book: opened)),
    );

    if (result != null) {
      final i = books.indexWhere((b) => b.path == result.path);
      if (i >= 0) {
        books[i] = result;
        await LibraryStore.save(books);
        if (mounted) setState(() {});
      }
    }
  }

  String pBasenameWithoutExt(String name) {
    final dot = name.lastIndexOf(".");
    if (dot <= 0) return name;
    return name.substring(0, dot);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tủ sách")),
      floatingActionButton: FloatingActionButton(
        onPressed: pickAndOpen,
        child: const Icon(Icons.add),
      ),
      body: books.isEmpty
          ? const Center(child: Text("Bấm (+) để mở EPUB. Sách đã mở sẽ tự lưu ở đây."))
          : ListView.separated(
              itemCount: books.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final b = books[i];
                final percent = (b.progress * 100).clamp(0, 100).toStringAsFixed(0);
                return ListTile(
                  title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text("Tiến độ: $percent%  •  Trang: ${b.lastPage + 1}"),
                  onTap: () async {
                    final result = await Navigator.push<BookItem>(
                      context,
                      MaterialPageRoute(builder: (_) => ReaderPage(book: b)),
                    );
                    if (result != null) {
                      books[i] = result;
                      await LibraryStore.save(books);
                      if (mounted) setState(() {});
                    }
                  },
                );
              },
            ),
    );
  }
}

/// =======================
/// UI: READER (mở là tính thời gian)
/// =======================
class ReaderPage extends StatefulWidget {
  final BookItem book;
  const ReaderPage({super.key, required this.book});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late BookItem book;

  List<String> pages = [];
  int pageIndex = 0;
  PageController? pc;

  int readSecondsToday = 0;
  Timer? readTimer;
  Timer? saveDebounce;

  @override
  void initState() {
    super.initState();
    book = widget.book;
    pageIndex = book.lastPage;

    ReadingTimeStore.loadSecondsToday().then((v) {
      if (!mounted) return;
      setState(() => readSecondsToday = v);
    });

    readTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      readSecondsToday += 1;
      if (readSecondsToday % 5 == 0) {
        await ReadingTimeStore.saveSecondsToday(readSecondsToday);
      }
      if (!mounted) return;
      setState(() {});
    });

    _loadPages();
  }

  Future<void> _loadPages() async {
    final list = await epubToTextPages(book.path);
    if (!mounted) return;

    final safeIndex = pageIndex.clamp(0, max(0, list.length - 1));
    pc = PageController(initialPage: safeIndex);

    setState(() {
      pages = list;
      pageIndex = safeIndex;
    });
  }

  void _scheduleSaveProgress() {
    saveDebounce?.cancel();
    saveDebounce = Timer(const Duration(milliseconds: 350), () {
      final total = pages.length;
      final prog = total <= 1 ? 0.0 : (pageIndex / (total - 1)).clamp(0.0, 1.0);
      book = book.copyWith(lastPage: pageIndex, progress: prog);
    });
  }

  @override
  void dispose() {
    readTimer?.cancel();
    saveDebounce?.cancel();
    pc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title),
        leading: BackButton(onPressed: () => Navigator.pop(context, book)),
      ),
      body: pages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                PageView.builder(
                  controller: pc,
                  onPageChanged: (i) {
                    setState(() => pageIndex = i);
                    _scheduleSaveProgress();
                  },
                  itemCount: pages.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Text(
                      pages[i],
                      style: const TextStyle(fontSize: 18, height: 1.6),
                    ),
                  ),
                ),

                // thời gian đọc hôm nay ở góc phải
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      formatHms(readSecondsToday),
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ),

                // số trang ở đáy
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text("${pageIndex + 1}/${pages.length}"),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
