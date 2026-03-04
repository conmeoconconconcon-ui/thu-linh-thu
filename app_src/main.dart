import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import 'pagination.dart';
import 'pet.dart';
import 'reading_rewards.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thu Linh Thu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int idx = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: idx,
        children: const [
          ReaderHome(),
          PetPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (v) => setState(() => idx = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book), label: "Đọc"),
          NavigationDestination(icon: Icon(Icons.pets), label: "Linh Thú"),
        ],
      ),
    );
  }
}

/// --------------------
/// TAB ĐỌC (Kindle)
/// --------------------
class ReaderHome extends StatefulWidget {
  const ReaderHome({super.key});
  @override
  State<ReaderHome> createState() => _ReaderHomeState();
}

class _ReaderHomeState extends State<ReaderHome> {
  bool loading = false;
  String? error;

  String bookTitle = "Đọc";
  List<String> kindlePages = [];
  int currentPage = 0;

  PetState? pet;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    PetStore.load().then((p) {
      if (mounted) setState(() => pet = p);
    });

    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final p = pet;
      if (p == null) return;

      final gift = await ReadingRewards.tick10s(p);
      await PetStore.save(p);

      if (!mounted) return;
      setState(() {});

      if (gift != null) _showGift(gift);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showGift(GiftResult gift) {
    final text = switch (gift.type) {
      GiftType.energy => "+${gift.amount} Tinh lực",
      GiftType.exp => "+${gift.amount} EXP",
      GiftType.food => "+${gift.amount} Thức ăn",
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("🎁 Nhận quà: $text"), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> pickAndOpenEpub() async {
    setState(() {
      loading = true;
      error = null;
      kindlePages = [];
      currentPage = 0;
      bookTitle = "Đọc";
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['epub'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => loading = false);
        return;
      }

      final Uint8List? bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Không đọc được bytes từ file EPUB.');
      }

      final zip = ZipDecoder().decodeBytes(bytes, verify: false);

      // lấy danh sách html theo OPF/spine, nếu fail thì fallback scan html
      final htmlPages = _getHtmlPages(zip);
      if (htmlPages.isEmpty) {
        throw Exception("Không tìm thấy HTML/XHTML trong EPUB.");
      }

      // Convert HTML -> TEXT và gộp lại
      final fullText = htmlPages.map((h) => htmlToPlainText(h)).join("\n\n");

      // paginate theo màn hình hiện tại
      final size = MediaQuery.of(context).size;
      final pages = paginateText(
        fullText: fullText,
        style: const TextStyle(fontSize: 18, height: 1.6),
        pageSize: size,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 90), // chừa chỗ bar dưới
      );

      setState(() {
        bookTitle = "EPUB";
        kindlePages = pages;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  // mỗi lần lật trang: active reading + thống kê
  Future<void> onPageTurn() async {
    await ReadingRewards.markUserActiveReading();

    final p = pet;
    if (p != null) {
      p.pagesTurnedToday += 1;
      await PetStore.save(p);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(bookTitle),
        actions: [
          IconButton(
            onPressed: loading ? null : pickAndOpenEpub,
            icon: const Icon(Icons.folder_open),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(error!)))
              : kindlePages.isEmpty
                  ? Center(
                      child: ElevatedButton.icon(
                        onPressed: pickAndOpenEpub,
                        icon: const Icon(Icons.folder_open),
                        label: const Text("Chọn EPUB"),
                      ),
                    )
                  : Column(
                      children: [
                        if (pet != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            child: Row(
                              children: [
                                Text("Lv.${pet!.level}  EXP ${pet!.exp}/${pet!.expToNext}"),
                                const Spacer(),
                                Text("⚡${pet!.energy}  🍖${pet!.food}"),
                              ],
                            ),
                          ),
                        Expanded(
                          child: KindlePager(
                            pages: kindlePages,
                            fontSize: 18,
                            onPageTurn: onPageTurn,
                            onPageChanged: (i) => setState(() => currentPage = i),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text("${currentPage + 1}/${kindlePages.length}"),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class KindlePager extends StatelessWidget {
  final List<String> pages;
  final double fontSize;
  final Future<void> Function() onPageTurn;
  final void Function(int) onPageChanged;

  const KindlePager({
    super.key,
    required this.pages,
    required this.fontSize,
    required this.onPageTurn,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final padding = const EdgeInsets.fromLTRB(16, 18, 16, 18);
    final style = TextStyle(fontSize: fontSize, height: 1.6);

    return PageView.builder(
      onPageChanged: (i) async {
        onPageChanged(i);
        await onPageTurn();
      },
      itemCount: pages.length,
      itemBuilder: (_, i) {
        return Padding(
          padding: padding,
          child: SelectableText(pages[i], style: style),
        );
      },
    );
  }
}

/// Lấy HTML pages từ EPUB: thử container->opf->spine, fail thì scan toàn bộ html
List<String> _getHtmlPages(Archive zip) {
  final byName = <String, ArchiveFile>{};
  for (final f in zip.files) {
    if (f.isFile) byName[f.name] = f;
  }

  String? readText(String path) {
    final f = byName[path];
    if (f == null) return null;
    final data = f.content as List<int>;
    try {
      return utf8.decode(data, allowMalformed: true);
    } catch (_) {
      return latin1.decode(data, allowInvalid: true);
    }
  }

  // container.xml
  final container = byName.keys.firstWhere(
    (k) => k.toLowerCase() == 'meta-inf/container.xml',
    orElse: () => '',
  );

  if (container.isNotEmpty) {
    final cxml = readText(container);
    if (cxml != null) {
      try {
        final doc = XmlDocument.parse(cxml);
        String? opfPath;
        for (final r in doc.findAllElements('rootfile')) {
          final fp = r.getAttribute('full-path');
          if (fp != null && fp.trim().isNotEmpty && !fp.trim().endsWith('/')) {
            opfPath = fp.trim();
            break;
          }
        }
        if (opfPath != null && byName.containsKey(opfPath)) {
          final opf = readText(opfPath);
          if (opf != null) {
            final opfDoc = XmlDocument.parse(opf);
            final opfDir = opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/')) : '';

            final manifest = <String, String>{};
            for (final item in opfDoc.findAllElements('item')) {
              final id = item.getAttribute('id');
              final href = item.getAttribute('href');
              if (id != null && href != null) manifest[id] = href;
            }

            final spine = <String>[];
            for (final itemref in opfDoc.findAllElements('itemref')) {
              final idref = itemref.getAttribute('idref');
              if (idref != null) spine.add(idref);
            }

            final pages = <String>[];
            for (final id in spine) {
              final href = manifest[id];
              if (href == null) continue;
              final path = opfDir.isEmpty ? href : "$opfDir/$href";
              final low = path.toLowerCase();
              if (!(low.endsWith('.xhtml') || low.endsWith('.html') || low.endsWith('.htm'))) continue;

              final html = readText(path);
              if (html != null) pages.add(html);
            }

            if (pages.isNotEmpty) return pages;
          }
        }
      } catch (_) {
        // ignore -> fallback
      }
    }
  }

  // fallback scan
  final htmlFiles = byName.keys
      .where((k) {
        final low = k.toLowerCase();
        return low.endsWith('.xhtml') || low.endsWith('.html') || low.endsWith('.htm');
      })
      .toList()
    ..sort();

  final pages = <String>[];
  for (final k in htmlFiles) {
    final html = readText(k);
    if (html != null && html.trim().isNotEmpty) pages.add(html);
  }
  return pages;
}

/// --------------------
/// TAB LINH THÚ
/// --------------------
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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = pet;
    if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final progress = (p.exp / p.expToNext).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(title: const Text("Linh Thú")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.pets, size: 44),
              title: Text("${stageName(p.stage)} • Lv.${p.level}"),
              subtitle: Text("Nhánh: ${branchName(p.branch)}"),
            ),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: Text("EXP: ${p.exp}/${p.expToNext}")),
            const SizedBox(height: 16),

            Row(
              children: [
                _stat("⚡ Tinh lực", p.energy),
                const SizedBox(width: 10),
                _stat("🍖 Thức ăn", p.food),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _stat("⏱ Giây đọc hôm nay", p.readSecondsToday),
                const SizedBox(width: 10),
                _stat("📄 Trang lật hôm nay", p.pagesTurnedToday),
              ],
            ),
            const SizedBox(height: 18),

            ElevatedButton(
              onPressed: p.canEvolve()
                  ? () async {
                      p.evolve();
                      await _save();
                    }
                  : null,
              child: Text(p.canEvolve() ? "Tiến hoá" : "Chưa đủ điều kiện"),
            ),

            const SizedBox(height: 14),
            const Align(alignment: Alignment.centerLeft, child: Text("Chọn nhánh:")),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: PetBranch.values.map((b) {
                return ChoiceChip(
                  label: Text(branchName(b)),
                  selected: p.branch == b,
                  onSelected: (_) async {
                    p.branch = b;
                    await _save();
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Expanded _stat(String label, int value) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text("$value", style: const TextStyle(fontSize: 18)),
            ],
          ),
        ),
      ),
    );
  }
}
