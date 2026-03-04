import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocsy_epub_viewer/epub_viewer.dart';

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
      theme: ThemeData(
        useMaterial3: true,
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

class _HomePageState extends State<HomePage> {
  static const _prefKeyEpubPath = 'saved_epub_path';
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    _loadSavedPath();
  }

  Future<void> _loadSavedPath() async {
    final sp = await SharedPreferences.getInstance();
    setState(() => _savedPath = sp.getString(_prefKeyEpubPath));
  }

  Future<void> _savePath(String path) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefKeyEpubPath, path);
    setState(() => _savedPath = path);
  }

  Future<void> _clearSaved() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_prefKeyEpubPath);
    setState(() => _savedPath = null);
  }

  Future<String?> _pickAndCopyEpubToAppStorage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    final originalPath = picked.path;
    if (originalPath == null) return null;

    final srcFile = File(originalPath);
    if (!await srcFile.exists()) return null;

    // Thư mục an toàn của app (không cần quyền truy cập bộ nhớ trên Android mới)
    final dir = await getApplicationDocumentsDirectory();
    final safeFolder = Directory(p.join(dir.path, 'epubs'));
    if (!await safeFolder.exists()) {
      await safeFolder.create(recursive: true);
    }

    // Đặt tên file trong app: giữ tên gốc + tránh trùng
    final baseName = p.basename(originalPath);
    final targetPath = p.join(safeFolder.path, baseName);

    // Nếu trùng tên thì thêm hậu tố
    String finalTarget = targetPath;
    if (await File(finalTarget).exists()) {
      final nameNoExt = p.basenameWithoutExtension(baseName);
      final ext = p.extension(baseName); // .epub
      final ts = DateTime.now().millisecondsSinceEpoch;
      finalTarget = p.join(safeFolder.path, '${nameNoExt}_$ts$ext');
    }

    final copied = await srcFile.copy(finalTarget);
    return copied.path;
  }

  Future<void> _openEpub(String filePath) async {
    // vocsy_epub_viewer đọc bằng filePath
    await EpubViewer.open(
      filePath,
      epubSource: EpubSource.local,
    );
  }

  Future<void> _chooseEpub() async {
    try {
      final copiedPath = await _pickAndCopyEpubToAppStorage();
      if (copiedPath == null) return;

      await _savePath(copiedPath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã thêm EPUB vào tủ sách.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi chọn EPUB: $e')),
      );
    }
  }

  Future<void> _readNow() async {
    final path = _savedPath;
    if (path == null) return;

    final f = File(path);
    if (!await f.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy file (đã bị xóa/di chuyển).')),
      );
      return;
    }

    try {
      await _openEpub(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi mở EPUB: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBook = _savedPath != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thư Linh Thú'),
        actions: [
          if (hasBook)
            IconButton(
              tooltip: 'Xóa sách đã lưu',
              onPressed: _clearSaved,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(child: Icon(Icons.menu_book_outlined)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasBook ? 'Đã có 1 EPUB trong tủ' : 'Chưa có EPUB',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            hasBook
                                ? p.basename(_savedPath!)
                                : 'Bấm “Chọn EPUB” để thêm sách từ điện thoại.',
                          ),
                          if (hasBook) ...[
                            const SizedBox(height: 6),
                            Text(
                              _savedPath!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: hasBook ? _readNow : null,
                      child: const Text('Đọc ngay'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _chooseEpub,
              icon: const Icon(Icons.upload_file),
              label: const Text('Chọn EPUB (từ điện thoại)'),
            ),
            const SizedBox(height: 10),
            const Text(
              'File sẽ được copy vào thư mục riêng của app để lần sau vẫn đọc được.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
