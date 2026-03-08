import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../home/presentation/home_page.dart';
import '../../module_details/presentation/module_details_page.dart';
import '../../scanner/presentation/scanner_page.dart';

// Riverpod Provayderlari: Sahifa indeksi va Sarlavha uchun
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);
final appBarTitleProvider = StateProvider<String>((ref) => 'Aristokrat Mebel');

class ShellPage extends ConsumerWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Joriy holatni o'qish
    final currentIndex = ref.watch(bottomNavIndexProvider);
    final title = ref.watch(appBarTitleProvider);

    // Dasturdagi asosiy oynalar
    final List<Widget> pages = [
      const HomePage(),
      const ModuleDetailsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      // Silliq (Fade) o'tish animatsiyasi
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: pages[currentIndex], // Joriy sahifani chizish
      ),
      // Markaziy Skaner tugmasi
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        shape: const CircleBorder(),
        elevation: 4,
        onPressed: () {
          // Skanerni butun ekran bo'ylab ustidan ochish
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ScannerPage()),
          );
        },
        child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      // Pastki Navigatsiya Paneli
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0, // Tugma va panel orasidagi ochiqlik
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
              const SizedBox(width: 48), // Skaner tugmasi uchun bo'sh joy
              _buildNavItem(
                icon: Icons.inventory_2_outlined,
                label: 'Furnitura',
                index: 1,
                currentIndex: currentIndex,
                onTap: () {
                  ref.read(bottomNavIndexProvider.notifier).state = 1;
                  // Sarlavha kelajakda ModuleDetails tomonidan API dan kelgan artikulga o'zgaradi
                  ref.read(appBarTitleProvider.notifier).state = 'Modul Ma\'lumotlari';
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Navigatsiya elementlarini chizuvchi yordamchi vidjet
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
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
