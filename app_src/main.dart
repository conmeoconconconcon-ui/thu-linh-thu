import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocsy_epub_viewer/epub_viewer.dart'; 
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(const ThuLinhThuApp());
}

class ThuLinhThuApp extends StatelessWidget {
  const ThuLinhThuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thư Linh Thú',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? lastEpubPath;
  String? lastEpubName;

  @override
  void initState() {
    super.initState();
    _loadLastBook();
    _setupEpubCallbacks();
  }

  Future<void> _loadLastBook() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      lastEpubPath = sp.getString('last_epub_path');
      lastEpubName = sp.getString('last_epub_name');
    });
  }

  void _setupEpubCallbacks() {
    // Lưu tiến độ (cfi) khi user đổi trang
    EpubViewer.locatorStream.listen((locator) async {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('last_epub_locator', locator);
      } catch (_) {}
    });
  }

  Future<void> _pickAndOpenEpub() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    final file = File(path);
    if (!await file.exists()) return;

    final name = result.files.single.name;

    final sp = await SharedPreferences.getInstance();
    await sp.setString('last_epub_path', path);
    await sp.setString('last_epub_name', name);

    setState(() {
      lastEpubPath = path;
      lastEpubName = name;
    });

    await _openEpub(path);
  }

  Future<void> _openLastBook() async {
    if (lastEpubPath == null) return;
    final file = File(lastEpubPath!);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy file EPUB đã lưu. Hãy chọn lại.')),
      );
      return;
    }
    await _openEpub(lastEpubPath!);
  }

  Future<void> _openEpub(String path) async {
    final sp = await SharedPreferences.getInstance();
    final lastLocator = sp.getString('last_epub_locator');

    await EpubViewer.open(
      path,
      lastLocation: lastLocator, // mở đúng trang lần trước
      themeData: EpubViewerThemeData(
        backgroundColor: Colors.white,
        // Bạn có thể chỉnh font/size sau
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLast = (lastEpubPath != null && lastEpubPath!.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thư Linh Thú'),
        actions: [
          IconButton(
            onPressed: _pickAndOpenEpub,
            icon: const Icon(Icons.upload_file),
            tooltip: 'Chọn EPUB',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _CardBook(
              title: hasLast ? (lastEpubName ?? 'Sách đã lưu') : 'Chưa có sách',
              subtitle: hasLast ? 'Bấm “Đọc tiếp” để mở trang đang đọc' : 'Bấm “Chọn EPUB” để bắt đầu',
              primaryText: hasLast ? 'Đọc tiếp' : 'Chọn EPUB',
              onPrimary: hasLast ? _openLastBook : _pickAndOpenEpub,
              secondaryText: 'Chọn EPUB',
              onSecondary: _pickAndOpenEpub,
            ),
            const SizedBox(height: 16),
            const Text(
              'Tip: File EPUB có thể nằm trong Downloads hoặc thư mục bạn lưu sách.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardBook extends StatelessWidget {
  final String title;
  final String subtitle;
  final String primaryText;
  final VoidCallback onPrimary;
  final String secondaryText;
  final VoidCallback onSecondary;

  const _CardBook({
    required this.title,
    required this.subtitle,
    required this.primaryText,
    required this.onPrimary,
    required this.secondaryText,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.menu_book)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                FilledButton(onPressed: onPrimary, child: Text(primaryText)),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: onSecondary, child: Text(secondaryText)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
