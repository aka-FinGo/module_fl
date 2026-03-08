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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length + 2, // +1 Instruction, +1 Spacer
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildInstructionCard(context);
        }

        if (index == history.length + 1) return const SizedBox(height: 100);

        final item = history[index - 1];
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
              ref.read(appBarTitleProvider.notifier).state =
                  'Modul: ${item.artikul}';
            },
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: fileId != null
                  ? Image.network(
                      'https://drive.google.com/thumbnail?id=$fileId&sz=w100-h100',
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover)
                  : Container(
                      width: 50,
                      height: 50,
                      color: AppColors.background,
                      child: const Icon(Icons.insert_drive_file, size: 20)),
            ),
            title: Text(item.artikul,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(item.nomi,
                style: const TextStyle(color: AppColors.accent, fontSize: 12)),
            trailing: const Icon(Icons.arrow_forward_ios,
                size: 16, color: AppColors.textGray),
          ),
        );
      },
    );
  }

  Widget _buildInstructionCard(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.primary.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withOpacity(0.1)),
      ),
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Qisqacha yo\'riqnoma',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 12),
            _stepItem('1', 'Moduldagi QR kodni skanerlang'),
            _stepItem('2', 'Chizma va videoni ko\'rib chiqing'),
            _stepItem('3', 'Furnituralarni birma-bir tekshiring'),
            _stepItem('4', 'Skanerlanganlar tarixda saqlanadi'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showDetailedGuide(context),
                icon: const Icon(Icons.menu_book, size: 18),
                label: const Text('Batafsil o\'qish'),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepItem(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            child: Text(num,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, color: Colors.black87))),
        ],
      ),
    );
  }

  void _showDetailedGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              const Text('Foydalanish bo\'yicha to\'liq qo\'llanma',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _guideSection('1. QR Skanerlash',
                  'Asosiy ekrandagi yashil skaner tugmasini bosing va mebel modulidagi QR kodni kameraga qarating.'),
              _guideSection('2. Chizmalarni ko\'rish',
                  'Chizma (PDF) tugmasini bosib, detallar o\'lchami va yig\'ish sxemasini ko\'rishingiz mumkin. Chizmani kattalashtirish uchun + va - tugmalaridan foydalaning.'),
              _guideSection('3. Video qo\'llanma',
                  'Agar modul uchun video mavjud bo\'lsa, "Video" bo\'limida uni ko\'rishingiz mumkin. Bu yig\'ish jarayonini osonlashtiradi.'),
              _guideSection('4. Furnitura nazorati',
                  'Har bir modul uchun kerakli furnituralar ro\'yxati berilgan. Ishlatilgan furnituralarni belgilab boring, ular avtomatik ravishda ro\'yxat oxiriga o\'tadi va ustidan chiziladi.'),
              _guideSection('5. Tarix',
                  'Skanerlangan barcha modullar "Tarix" sahifasida saqlanadi. Istalgan vaqtda ularga qaytib ma\'lumotlarni ko\'rishingiz mumkin.'),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guideSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 8),
          Text(content,
              style: const TextStyle(
                  fontSize: 14, color: Colors.black87, height: 1.5)),
        ],
      ),
    );
  }
}
