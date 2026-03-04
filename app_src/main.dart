import 'dart:io';
import 'dart:typed_data';

import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  bool darkMode = false;
  double fontSize = 18;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EPUB Reader',
      theme: ThemeData(
        brightness: darkMode ? Brightness.dark : Brightness.light,
      ),
      home: HomePage(
        toggleTheme: () {
          setState(() {
            darkMode = !darkMode;
          });
        },
        fontSize: fontSize,
        changeFont: (v) {
          setState(() {
            fontSize = v;
          });
        },
      ),
    );
  }
}

class HomePage extends StatefulWidget {

  final Function toggleTheme;
  final double fontSize;
  final Function(double) changeFont;

  const HomePage({
    super.key,
    required this.toggleTheme,
    required this.fontSize,
    required this.changeFont,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  List<String> books = [];

  Future pickBook() async {

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      withData: true,
    );

    if (result == null) return;

    final file = result.files.first;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          bytes: file.bytes!,
          fontSize: widget.fontSize,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Thư Linh Thú"),
        actions: [

          IconButton(
            icon: const Icon(Icons.dark_mode),
            onPressed: () {
              widget.toggleTheme();
            },
          ),

          IconButton(
            icon: const Icon(Icons.text_fields),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) {
                  return AlertDialog(
                    title: const Text("Cỡ chữ"),
                    content: Slider(
                      value: widget.fontSize,
                      min: 14,
                      max: 30,
                      onChanged: (v) {
                        widget.changeFont(v);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),

      body: Center(
        child: ElevatedButton(
          onPressed: pickBook,
          child: const Text("Mở EPUB"),
        ),
      ),
    );
  }
}

class ReaderPage extends StatefulWidget {

  final Uint8List bytes;
  final double fontSize;

  const ReaderPage({
    super.key,
    required this.bytes,
    required this.fontSize,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {

  late EpubBook book;
  int chapterIndex = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    openBook();
  }

  Future openBook() async {

    book = await EpubReader.readBook(widget.bytes);

    setState(() {
      loading = false;
    });
  }

  String getChapterHtml() {

    final chapter = book.Chapters![chapterIndex];

    return chapter.HtmlContent ?? "";
  }

  void nextChapter() {

    if (chapterIndex < book.Chapters!.length - 1) {
      setState(() {
        chapterIndex++;
      });
    }
  }

  void prevChapter() {

    if (chapterIndex > 0) {
      setState(() {
        chapterIndex--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(

      appBar: AppBar(
        title: Text(book.Title ?? "Book"),
      ),

      body: Column(
        children: [

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Html(
                data: getChapterHtml(),
                style: {
                  "body": Style(
                    fontSize: FontSize(widget.fontSize),
                  )
                },
              ),
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [

              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: prevChapter,
              ),

              Text(
                "${chapterIndex + 1}/${book.Chapters!.length}",
              ),

              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: nextChapter,
              ),
            ],
          )
        ],
      ),
    );
  }
}
