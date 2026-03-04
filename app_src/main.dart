import 'dart:async';
import 'package:flutter/material.dart';

void main() => runApp(const ThuLinhThuApp());

class ThuLinhThuApp extends StatelessWidget {
  const ThuLinhThuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thư Linh Thú',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF7B5CFF)),
      home: const MainShell(),
    );
  }
}

class GameState {
  static int exp = 0;
  static int totalReadSeconds = 0;
  static int level = 1;

  static void addReadSecond() {
    totalReadSeconds += 1;
    exp = totalReadSeconds; // 1 giây = 1 EXP (demo). Sau này đổi theo phút/trang.
    level = 1 + (exp ~/ 600); // mỗi 10 phút lên 1 cấp
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      Home(onGoRead: () => setState(() => tab = 1)),
      Reader(onChanged: () => setState(() {})),
      const Bag(),
      const Profile(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thư Linh Thú'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text('EXP ${GameState.exp} • Cấp ${GameState.level}')),
          ),
        ],
      ),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Trang chủ'),
          NavigationDestination(icon: Icon(Icons.menu_book), label: 'Đọc'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Túi đồ'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Hồ sơ'),
        ],
      ),
    );
  }
}

class Home extends StatelessWidget {
  final VoidCallback onGoRead;
  const Home({super.key, required this.onGoRead});

  @override
  Widget build(BuildContext context) {
    final mins = GameState.totalReadSeconds ~/ 60;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Text('🐉')),
            title: Text('Linh thú: Tiểu Long (Cấp ${GameState.level})'),
            subtitle: Text('Đã đọc: $mins phút • EXP: ${GameState.exp}'),
            trailing: FilledButton(onPressed: onGoRead, child: const Text('Đọc ngay')),
          ),
        ),
      ],
    );
  }
}

class Reader extends StatefulWidget {
  final VoidCallback onChanged;
  const Reader({super.key, required this.onChanged});

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  Timer? timer;
  int session = 0;
  bool running = false;

  void start() {
    if (running) return;
    setState(() => running = true);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => session++);
      GameState.addReadSecond();
      widget.onChanged();
    });
  }

  void stop() {
    timer?.cancel();
    timer = null;
    setState(() => running = false);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = session ~/ 60, s = session % 60;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(child: ListTile(title: const Text('Đọc sách (demo)'), subtitle: Text('Phiên này: ${m}p ${s}s'))),
          const SizedBox(height: 12),
          const Expanded(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: SingleChildScrollView(
                  child: Text('Đây là khung đọc demo.\n\nBấm “Bắt đầu” để tích thời gian đọc → tăng EXP → lên cấp linh thú.'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: running ? null : start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Bắt đầu'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: running ? stop : null,
                  icon: const Icon(Icons.pause),
                  label: const Text('Tạm dừng'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class Bag extends StatelessWidget {
  const Bag({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Túi đồ (demo)'));
}

class Profile extends StatelessWidget {
  const Profile({super.key});
  @override
  Widget build(BuildContext context) {
    final hours = (GameState.totalReadSeconds / 3600).toStringAsFixed(2);
    return Center(child: Text('Tổng thời gian đọc: $hours giờ'));
  }
}
