import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:epub_view/epub_view.dart';

void main() {
  runApp(const ThuLinhThuApp());
}

class ThuLinhThuApp extends StatelessWidget {
  const ThuLinhThuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thu Linh Thu',
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

class _HomePageState extends State<HomePage> {
  static const _kLastEpubPath = 'last_epub_path';

  String? _epubPath;
  String? _epubName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kLastEpubPath);

    if (saved != null && saved.isNotEmpty) {
      final f = File(saved);
      if (await f.exists()) {
        _epubPath = saved;
        _epubName = p.basename(saved);
      } else {
        // File bị xóa/mất
        await prefs.remove(_kLastEpubPath);
        _epubPath = null;
        _epubName = null;
      }
    }

    setState(() => _loading = false);
  }

  Future<void> _pickEpubFromPhone() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final pickedPath = result.files.single.path;
    if (pickedPath == null) return;

    // Copy vào thư mục app để ổn định (tránh file bị mất quyền/di chuyển)
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(pickedPath);
    final destPath = p.join(appDir.path, fileName);

    try {
      await File(pickedPath).copy(destPath);
    } catch (_) {
      // Nếu copy fail (một số máy), dùng path gốc luôn
      // nhưng có thể bị mất quyền sau này
    }

    final finalPath = await File(destPath).exists() ? destPath : pickedPath;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastEpubPath, finalPath);

    setState(() {
      _epubPath = finalPath;
      _epubName = p.basename(finalPath);
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã chọn: ${_epubName ?? "EPUB"}')),
    );
  }

  Future<void> _openEpub() async {
    if (_epubPath == null) return;

    // Mở EPUB bằng vocsy_epub_viewer
    await VocsyEpub.setConfig(
      themeColor: Theme.of(context).colorScheme.primary,
      identifier: "thu_linh_thu_epub",
      scrollDirection: EpubScrollDirection.ALLDIRECTIONS,
      allowSharing: true,
      enableTts: false,
      nightMode: false,
    );

    await VocsyEpub.open(
      _epubPath!,
      lastLocation: EpubLocator.fromJson({}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thu Linh Thú'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              child: Icon(Icons.menu_book, color: cs.onPrimaryContainer),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _epubName ?? 'Chưa chọn EPUB',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickEpubFromPhone,
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Chọn EPUB (từ điện thoại)'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _epubPath == null ? null : _openEpub,
                                child: const Text('Đọc ngay'),
                              ),
                            ),
                          ],
                        ),
                        if (_epubPath != null) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Đường dẫn lưu: $_epubPath',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
