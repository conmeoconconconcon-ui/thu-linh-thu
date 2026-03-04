import 'dart:io';
import 'dart:typed_data';

import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thư Linh Thú',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const LibraryPage(),
    );
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const _kLastPath = 'last_epub_path';
  String? lastPath;

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    final sp = await SharedPreferences.getInstance();
    setState(() => lastPath = sp.getString(_kLastPath));
  }

  Future<void> _saveLast(String path) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLastPath, path);
    setState(() => lastPath = path);
  }

  Future<void> pickEpub() async {
    // withData=true để tránh lỗi content:// không đọc được
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final f = result.files.first;
    final bytes = f.bytes; // có thể null trên vài máy
    final pickedPath = f.path;

    final docs = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docs.path, 'epubs'));
    await outDir.create(recursive: true);

    final safeName = (f.name.isNotEmpty) ? f.name : 'book.epub';
    final outPath = p.join(outDir.path, safeName);

    // Lưu theo kiểu “copy vào app” để lần sau mở ổn định
    if (bytes != null && bytes.isNotEmpty) {
      await File(outPath).writeAsBytes(bytes, flush: true);
      await _saveLast(outPath);
    } else if (pickedPath != null) {
      await File(pickedPath).copy(outPath);
      await _saveLast(outPath);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không lấy được file. Thử chọn lại.')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderPage(epubPath: outPath)),
    );
  }

  Future<void> openLast() async {
    if (lastPath == null) return;
    final file = File(lastPath!);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File đã lưu không còn tồn tại. Hãy chọn lại EPUB.')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderPage(epubPath: lastPath!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLast = lastPath != null && lastPath!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Thư Linh Thú — Tủ sách')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.menu_book)),
                title: Text(hasLast ? p.basename(lastPath!) : 'Chưa có sách'),
                subtitle: Text(hasLast ? 'Bấm “Đọc tiếp” để mở lại' : 'Bấm “Chọn EPUB” để bắt đầu'),
                trailing: FilledButton(
                  onPressed: hasLast ? openLast : null,
                  child: const Text('Đọc tiếp'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: pickEpub,
              icon: const Icon(Icons.upload_file),
              label: const Text('Chọn EPUB từ điện thoại'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Mẹo: App sẽ copy EPUB vào thư mục riêng để tránh lỗi “một số file không mở được”.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class ReaderPage extends StatefulWidget {
  final String epubPath;
  const ReaderPage({super.key, required this.epubPath});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  String title = 'Đang tải...';
  List<_Chapter> chapters = [];
  int index = 0;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadEpub();
  }

  Future<void> _loadEpub() async {
    try {
      final bytes = await File(widget.epubPath).readAsBytes();
      final book = await EpubReader.readBook(bytes);

      title = book.Title ?? p.basename(widget.epubPath);

      final List<_Chapter> out = [];
      void walk(List<EpubChapter>? list) {
        if (list == null) return;
        for (final c in list) {
          final t = (c.Title ?? '').trim();
          final html = c.HtmlContent;
          if ((html != null && html.trim().isNotEmpty) || t.isNotEmpty) {
            out.add(_Chapter(t.isEmpty ? 'Chương ${out.length + 1}' : t, html ?? ''));
          }
          if (c.SubChapters != null && c.SubChapters!.isNotEmpty) {
            walk(c.SubChapters);
          }
        }
      }

      walk(book.Chapters);

      if (out.isEmpty) {
        throw Exception('EPUB không có nội dung hoặc cấu trúc không hỗ trợ.');
      }

      setState(() {
        chapters = out;
        index = 0;
        loading = false;
      });
    } catch (e) {
      setState(() {
        loading = false;
        error = '$e';
      });
    }
  }

  void _next() {
    if (index < chapters.length - 1) setState(() => index++);
  }

  void _prev() {
    if (index > 0) setState(() => index--);
  }

  @override
  Widget build(BuildContext context) {
    final has = chapters.isNotEmpty;
    final chapTitle = has ? chapters[index].title : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (has)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text('${index + 1}/${chapters.length}'),
              ),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (error != null)
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Không mở được EPUB', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(error!),
                      const SizedBox(height: 12),
                      const Text(
                        'Nếu EPUB có DRM (mua từ store) hoặc file hỏng, app có thể không đọc được.',
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (chapTitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(chapTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Html(data: chapters[index].html),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: index == 0 ? null : _prev,
                              icon: const Icon(Icons.chevron_left),
                              label: const Text('Trước'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: index >= chapters.length - 1 ? null : _next,
                              icon: const Icon(Icons.chevron_right),
                              label: const Text('Sau'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _Chapter {
  final String title;
  final String html;
  _Chapter(this.title, this.html);
}
