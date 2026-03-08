import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../home/presentation/home_page.dart';
import '../../module_details/presentation/module_details_page.dart';
import '../../module_details/presentation/media_view_page.dart';
import '../../scanner/presentation/scanner_page.dart';
import '../../../data/repositories/api_repository.dart';

final bottomNavIndexProvider = StateProvider<int>((ref) => 0);
final appBarTitleProvider = StateProvider<String>((ref) => 'Aristokrat Mebel');

class ShellPage extends ConsumerWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(bottomNavIndexProvider);
    final title = ref.watch(appBarTitleProvider);
    final moduleData = ref.watch(moduleDataProvider);

    final List<Widget> pages = [
      const HomePage(),
      const MediaViewPage(type: 'pdf'),
      const MediaViewPage(type: 'video'),
      const ModuleDetailsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: pages[currentIndex],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        shape: const CircleBorder(),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ScannerPage())),
        child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 6.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _navItem(ref, Icons.history, 'Tarix', 0, currentIndex, true),
            _navItem(ref, Icons.architecture, 'Chizma', 1, currentIndex, moduleData != null),
            const SizedBox(width: 40),
            _navItem(ref, Icons.play_circle_outline, 'Video', 2, currentIndex, moduleData != null),
            _navItem(ref, Icons.inventory_2_outlined, 'Furnitura', 3, currentIndex, moduleData != null),
          ],
        ),
      ),
    );
  }

  Widget _navItem(WidgetRef ref, IconData icon, String label, int index, int current, bool enabled) {
    final color = enabled ? (index == current ? AppColors.accent : AppColors.textGray) : Colors.grey.shade300;
    return InkWell(
      onTap: enabled ? () {
        ref.read(bottomNavIndexProvider.notifier).state = index;
        if (index == 0) ref.read(appBarTitleProvider.notifier).state = 'Aristokrat Mebel';
      } : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: index == current ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}
