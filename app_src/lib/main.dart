import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pagination.dart';
import 'pet.dart';
import 'reading_rewards.dart';

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
      theme: ThemeData(useMaterial3: true),
      home: const ReaderHome(),
    );
  }
}

class ReaderHome extends StatefulWidget {
  const ReaderHome({super.key});

  @override
  State<ReaderHome> createState() => _ReaderHomeState();
}

class _ReaderHomeState extends State<ReaderHome> {
  List<String> pages = [];
  int pageIndex = 0;
  String bookTitle = "Chưa chọn sách";

  PetState? pet;
  bool _readingActive = false;

  @override
  void initState() {
    super.initState();
    PetStore.load().then((p) => setState(() => pet = p));
    _startRewardLoop();
  }

  Future<void> _startRewardLoop() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 10));
      if (!mounted) return;
      if (pet == null) continue;

      // chỉ tick khi user đang đọc
      if (_readingActive && pages.isNotEmpty) {
        await ReadingRewards.markUserActiveReading();
        final gift = await ReadingRewards.tick10s(pet!);
        await PetStore.save(pet!);

        if (!mounted) return;
        setState(() {});

        if (gift != null) _showGift(gift);
      }
    }
  }

  void _showGift(GiftResult gift) {
    final msg = switch (gift.type) {
      GiftType.energy => "+${gift.amount} Tinh lực",
      GiftType.exp => "+${gift.amount} EXP",
      GiftType.food => "+${gift.amount} Thức ăn",
    };

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(gift.title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  Future<void> pickEpub() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      withData: true,
    );
    if (result == null) return;

    final file = result.files.single;
    final Uint8List bytes = file.bytes!;
    final name = file.name;

    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      // lấy tất cả html/xhtml
      final htmlPages = <String>[];
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final n = f.name.toLowerCase();
        if (n.endsWith(".html") || n.endsWith(".xhtml")) {
          htmlPages.add(utf8.decode(f.content));
        }
      }

      if (htmlPages.isEmpty) {
        throw Exception("EPUB không có file html/xhtml");
      }

      final fullText = htmlPages.map(htmlToPlainText).join("\n\n");
      final newPages = paginateText(fullText, maxCharsPerPage: 1800);

      setState(() {
        bookTitle = name;
        pages = newPages;
        pageIndex = 0;
      });
    } catch (e) {
      setState(() {
        pages = [];
        pageIndex = 0;
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Không mở được EPUB"),
          content: Text("Lỗi: $e"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            )
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pet;

    return Scaffold(
      appBar: AppBar(
        title: Text(bookTitle),
        actions: [
          IconButton(
            onPressed: pickEpub,
            icon: const Icon(Icons.folder_open),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PetPage()),
              );
            },
            icon: const Icon(Icons.pets),
          ),
        ],
      ),
      body: pages.isEmpty
          ? const Center(child: Text("Bấm icon folder để chọn EPUB"))
          : GestureDetector(
              onTapDown: (_) => setState(() => _readingActive = true),
              onTapUp: (_) => setState(() => _readingActive = true),
              onPanDown: (_) => setState(() => _readingActive = true),
              child: PageView.builder(
                itemCount: pages.length,
                onPageChanged: (i) {
                  setState(() {
                    pageIndex = i;
                    _readingActive = true;
                  });
                },
                itemBuilder: (_, i) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: Text(
                        pages[i],
                        style: const TextStyle(fontSize: 18, height: 1.6),
                      ),
                    ),
                  );
                },
              ),
            ),
      bottomNavigationBar: p == null
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Text("${pageIndex + 1}/${pages.length}")),
                  Text("EXP: ${p.exp}  |  TL: ${p.energy}  |  Food: ${p.food}"),
                ],
              ),
            ),
    );
  }
}

class PetStore {
  static const _kPet = "pet_state_v1";

  static Future<PetState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kPet);
    if (s == null) return PetState.initial();
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return PetState.fromJson(j);
    } catch (_) {
      return PetState.initial();
    }
  }

  static Future<void> save(PetState pet) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPet, jsonEncode(pet.toJson()));
  }
}

class PetPage extends StatefulWidget {
  const PetPage({super.key});

  @override
  State<PetPage> createState() => _PetPageState();
}

class _PetPageState extends State<PetPage> {
  PetState? pet;

  @override
  void initState() {
    super.initState();
    PetStore.load().then((p) => setState(() => pet = p));
  }

  String stageName(PetStage s) => switch (s) {
        PetStage.egg => "Trứng",
        PetStage.baby => "Ấu thú",
        PetStage.beast => "Linh thú",
        PetStage.saint => "Thánh thú",
        PetStage.god => "Thần thú",
      };

  String branchName(PetBranch b) => switch (b) {
        PetBranch.guardian => "Hộ Pháp",
        PetBranch.wisdom => "Trí Linh",
        PetBranch.speed => "Tốc Đọc",
      };

  Future<void> _save() async {
    if (pet == null) return;
    await PetStore.save(pet!);
  }

  @override
  Widget build(BuildContext context) {
    final p = pet;
    if (p == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Linh thú")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text("Giai đoạn: ${stageName(p.stage)}", style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text("Nhánh: ${branchName(p.branch)}", style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            Text("EXP: ${p.exp}"),
            Text("Tinh lực: ${p.energy}"),
            Text("Thức ăn: ${p.food}"),
            const Divider(height: 32),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Chọn nhánh phát triển:", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),

            Wrap(
              spacing: 10,
              children: PetBranch.values.map((b) {
                final selected = b == p.branch;
                return ChoiceChip(
                  label: Text(branchName(b)),
                  selected: selected,
                  onSelected: (_) async {
                    setState(() => p.branch = b);
                    await _save();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: () async {
                p.addFood(-1);
                p.addEnergy(15);
                await _save();
                setState(() {});
              },
              child: const Text("Cho ăn (tốn 1 food, +15 tinh lực)"),
            ),
          ],
        ),
      ),
    );
  }
}
