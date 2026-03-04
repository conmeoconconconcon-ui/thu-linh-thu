import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:epub_view/epub_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EPUB Reader',
      theme: ThemeData(primarySwatch: Colors.blue),
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

  void pickEpub() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );

    if (result != null) {
      String path = result.files.single.path!;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReaderPage(path),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Thu Linh Thu")),
      body: Center(
        child: ElevatedButton(
          onPressed: pickEpub,
          child: const Text("Chọn EPUB từ điện thoại"),
        ),
      ),
    );
  }
}

class ReaderPage extends StatelessWidget {
  final String path;

  const ReaderPage(this.path, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Đọc sách")),
      body: EpubView(
        controller: EpubController(
          document: EpubDocument.openFile(File(path)),
        ),
      ),
    );
  }
}
