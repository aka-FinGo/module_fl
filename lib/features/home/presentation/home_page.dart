import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/api_repository.dart';
import '../../shell/presentation/shell_page.dart';
import '../controllers/history_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

    if (history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_outlined, size: 64, color: AppColors.textGray),
            SizedBox(height: 16),
            Text('Hali tarix yo\'q', style: TextStyle(color: AppColors.textGray, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length + 1,
      itemBuilder: (context, index) {
        if (index == history.length) return const SizedBox(height: 100);
        
        final item = history[index];
        String? fileId;
        if (item.pdfUrl.isNotEmpty) {
          final match = RegExp(r'[-\w]{25,}').firstMatch(item.pdfUrl);
          if (match != null) fileId = match.group(0);
        }

        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            onTap: () {
              ref.read(moduleDataProvider.notifier).state = item;
              ref.read(bottomNavIndexProvider.notifier).state = 3; // Furnitura
              ref.read(appBarTitleProvider.notifier).state = 'Modul: ${item.artikul}';
            },
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: fileId != null 
                ? Image.network('https://drive.google.com/thumbnail?id=$fileId&sz=w100-h100', width: 50, height: 50, fit: BoxFit.cover)
                : Container(width: 50, height: 50, color: AppColors.background, child: const Icon(Icons.insert_drive_file, size: 20)),
            ),
            title: Text(item.artikul, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(item.nomi, style: const TextStyle(color: AppColors.accent, fontSize: 12)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textGray),
          ),
        );
      },
    );
  }
}
