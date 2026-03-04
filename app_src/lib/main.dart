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

  Future<void> pickBook() async {

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );

    if (result == null) return;

    final path = result.files.single.path!;

    setState(() {
      books.add(path);
    });

  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text("Tủ sách")),

      floatingActionButton: FloatingActionButton(
        onPressed: pickBook,
        child: const Icon(Icons.add),
      ),

      body: ListView.builder(
        itemCount: books.length,
        itemBuilder: (_, i) {

          final path = books[i];
          final name = path.split("/").last;

          return ListTile(
            title: Text(name),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReaderPage(path: path),
                ),
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

  int readSeconds = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();

    loadBook();

    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        setState(() {
          readSeconds++;
        });
      },
    );
  }

  Future<void> loadBook() async {

    final bytes = await File(widget.path).readAsBytes();

    final zip = ZipDecoder().decodeBytes(bytes);

    List<String> htmlFiles = [];

    for (final file in zip.files) {
      if (!file.isFile) continue;

      final name = file.name.toLowerCase();

      if (name.endsWith(".html") || name.endsWith(".xhtml")) {

        final data = file.content as List<int>;

        htmlFiles.add(
          utf8.decode(data, allowMalformed: true),
        );

      }
    }

    final text = htmlFiles
        .map((e) => e.replaceAll(RegExp(r"<[^>]*>"), " "))
        .join("\n");

    final pageSize = 1800;

    final list = <String>[];

    for (int i = 0; i < text.length; i += pageSize) {

      final end = min(i + pageSize, text.length);

      list.add(
        text.substring(i, end),
      );

    }

    final int safeIndex =
        pageIndex.clamp(0, list.length - 1).toInt();

    controller =
        PageController(initialPage: safeIndex);

    setState(() {
      pages = list;
      pageIndex = safeIndex;
    });

  }

  @override
  void dispose() {
    timer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  String formatTime(int s) {

    final m = s ~/ 60;
    final sec = s % 60;

    return "${m}m ${sec}s";
  }

  @override
  Widget build(BuildContext context) {

    if (pages.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(

      appBar: AppBar(),

      body: Stack(
        children: [

          PageView.builder(
            controller: controller,
            itemCount: pages.length,

            onPageChanged: (i) {
              pageIndex = i;
            },

            itemBuilder: (_, i) {

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  pages[i],
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.6,
                  ),
                ),
              );

            },
          ),

          Positioned(
            right: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black54,
              child: Text(
                formatTime(readSeconds),
              ),
            ),
          ),

        ],
      ),
    );
  }
}
