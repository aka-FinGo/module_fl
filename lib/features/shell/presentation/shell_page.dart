import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../home/presentation/home_page.dart';
import '../../module_details/presentation/module_details_page.dart';
import '../../module_details/presentation/media_view_page.dart';
import '../../scanner/presentation/scanner_page.dart';
import '../../../data/repositories/api_repository.dart';

final bottomNavIndexProvider = StateProvider<int>((ref) => 0);
final appBarTitleProvider    = StateProvider<String>((ref) => 'Aristokrat Mebel');
final isFullScreenProvider   = StateProvider<bool>((ref) => false);

class ShellPage extends ConsumerWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(bottomNavIndexProvider);
    final title        = ref.watch(appBarTitleProvider);
    final moduleData   = ref.watch(moduleDataProvider);
    final isFullScreen = ref.watch(isFullScreenProvider);

    // ── IndexedStack: barcha sahifalar tirik, PDF/Video state aralashmaydi
    const pages = [
      HomePage(),
      MediaViewPage(type: 'pdf',   key: ValueKey('pdf_page')),
      MediaViewPage(type: 'video', key: ValueKey('video_page')),
      ModuleDetailsPage(),
    ];

    return Scaffold(
      appBar: isFullScreen
          ? null
          : AppBar(
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
      body: IndexedStack(
        index: currentIndex,
        children: pages,
      ),
      floatingActionButton: isFullScreen
          ? null
          : FloatingActionButton(
              backgroundColor: AppColors.accent,
              shape: const CircleBorder(),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ScannerPage())),
              child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: isFullScreen
          ? null
          : BottomAppBar(
              shape: const CircularNotchedRectangle(),
              notchMargin: 6.0,
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _navItem(ref, Icons.history,              'Bosh sahifa', 0, currentIndex, true),
                  _navItem(ref, Icons.architecture,         'Chizma',      1, currentIndex, moduleData != null),
                  const SizedBox(width: 40),
                  _navItem(ref, Icons.play_circle_outline,  'Video',       2, currentIndex, moduleData != null),
                  _navItem(ref, Icons.inventory_2_outlined, 'Furnitura',   3, currentIndex, moduleData != null),
                ],
              ),
            ),
    );
  }

  Widget _navItem(WidgetRef ref, IconData icon, String label,
      int index, int current, bool enabled) {
    final isActive = index == current;
    final color = enabled
        ? (isActive ? AppColors.accent : Colors.white70)
        : Colors.white24;

    return Expanded(
      child: InkWell(
        onTap: enabled
            ? () {
                ref.read(bottomNavIndexProvider.notifier).state = index;
                if (index == 0) {
                  ref.read(appBarTitleProvider.notifier).state = 'Aristokrat Mebel';
                }
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: isActive ? 24 : 20),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
              if (isActive)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  height: 2,
                  width: 12,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
