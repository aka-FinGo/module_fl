import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../home/presentation/home_page.dart';
import '../../module_details/presentation/module_details_page.dart';
import '../../scanner/presentation/scanner_page.dart';

// Global holat provayderlari
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);
final appBarTitleProvider = StateProvider<String>((ref) => 'Aristokrat Mebel');

class ShellPage extends ConsumerWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(bottomNavIndexProvider);
    final title = ref.watch(appBarTitleProvider);

    final List<Widget> pages = [
      const HomePage(),
      const ModuleDetailsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: pages[currentIndex],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        shape: const CircleBorder(),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ScannerPage()),
          );
        },
        child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                icon: Icons.history,
                label: 'Tarix',
                index: 0,
                currentIndex: currentIndex,
                onTap: () {
                  ref.read(bottomNavIndexProvider.notifier).state = 0;
                  ref.read(appBarTitleProvider.notifier).state = 'Aristokrat Mebel';
                },
              ),
              const SizedBox(width: 48),
              _buildNavItem(
                icon: Icons.inventory_2_outlined,
                label: 'Furnitura',
                index: 1,
                currentIndex: currentIndex,
                onTap: () {
                  ref.read(bottomNavIndexProvider.notifier).state = 1;
                  // Sarlavhani faqat agar ma'lumot bo'lmasa o'zgartiramiz
                  if (ref.read(appBarTitleProvider) == 'Aristokrat Mebel') {
                    ref.read(appBarTitleProvider.notifier).state = 'Modul Ma\'lumotlari';
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required int currentIndex,
    required VoidCallback onTap,
  }) {
    final isSelected = index == currentIndex;
    final color = isSelected ? AppColors.accent : AppColors.textGray;
    
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 26),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}
