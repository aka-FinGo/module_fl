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
      itemCount: history.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return _buildInstructionCard(context);
        if (index == history.length + 1) return const SizedBox(height: 100);

        final item = history[index - 1];

        // Thumbnail uchun Drive file ID olish
        // Avval pdfUrl dan, bo'lmasa tgPdfId ni Drive URL sifatida ishlatib bo'lmaydi
        // Shuning uchun faqat pdfUrl dan Drive ID olamiz
        String? driveFileId;
        if (item.pdfUrl.isNotEmpty && item.pdfUrl.contains('drive.google.com')) {
          final match = RegExp(r'[-\w]{25,}').firstMatch(item.pdfUrl);
          if (match != null) driveFileId = match.group(0);
        }

        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            onTap: () {
              ref.read(moduleDataProvider.notifier).state = item;
              ref.read(bottomNavIndexProvider.notifier).state = 3;
              ref.read(appBarTitleProvider.notifier).state = 'Modul: ${item.artikul}';
            },
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: driveFileId != null
                  ? Image.network(
                      'https://lh3.googleusercontent.com/d/$driveFileId',
                      width: 50, height: 50, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _iconBox(Icons.picture_as_pdf, AppColors.danger),
                    )
                  // Telegram PDF bo'lsa — PDF ikonkasi ko'rsatamiz
                  : item.tgPdfId.isNotEmpty
                      ? _iconBox(Icons.picture_as_pdf, AppColors.danger)
                      : _iconBox(Icons.insert_drive_file, AppColors.textGray),
            ),
            title: Text(item.artikul,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nomi,
                    style: const TextStyle(color: AppColors.accent, fontSize: 12)),
                Row(
                  children: [
                    if (item.tgPdfId.isNotEmpty || item.pdfUrl.isNotEmpty)
                      const Text('📄 ', style: TextStyle(fontSize: 11)),
                    if (item.tgVideoId.isNotEmpty || item.videoUrl.isNotEmpty)
                      const Text('🎬 ', style: TextStyle(fontSize: 11)),
                    Text(
                      '${item.furnituralar.values.fold(0, (s, v) => s + v.length)} furnitura',
                      style: const TextStyle(fontSize: 11, color: AppColors.textGray),
                    ),
                  ],
                ),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios,
                size: 16, color: AppColors.textGray),
          ),
        );
      },
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 50, height: 50,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, color: color, size: 24),
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
            const Row(children: [
              Icon(Icons.info_outline, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Qisqacha yo\'riqnoma',
                  style: TextStyle(fontWeight: FontWeight.bold,
                      fontSize: 16, color: AppColors.primary)),
            ]),
            const SizedBox(height: 12),
            _stepItem('1', 'Moduldagi QR kodni skanerlang'),
            _stepItem('2', 'Chizma va videoni ko\'rib chiqing'),
            _stepItem('3', 'Furnituralarni birma-bir tekshiring'),
            _stepItem('4', 'Skanerlanganlar tarixda saqlanadi'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showGuide(context),
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
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            child: Text(num, style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text,
              style: const TextStyle(fontSize: 13, color: Colors.black87))),
        ],
      ),
    );
  }

  void _showGuide(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7, maxChildSize: 0.9, minChildSize: 0.5,
        expand: false,
        builder: (context, sc) => SingleChildScrollView(
          controller: sc, padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            const Text('To\'liq qo\'llanma',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _guide('1. QR Skanerlash',
                'Yashil skaner tugmasini bosing va QR kodni kameraga qarating.'),
            _guide('2. Chizmalar',
                'Chizma (PDF) tugmasini bosib yig\'ish sxemasini ko\'ring.'),
            _guide('3. Video',
                '"Video" bo\'limida yig\'ish videosini tomosha qiling.'),
            _guide('4. Furnitura',
                'Furnituralarni belgilab boring — ular pastga tushadi.'),
            _guide('5. Tarix',
                'Skanerlangan modullar "Bosh sahifa"da saqlanadi.'),
          ]),
        ),
      ),
    );
  }

  Widget _guide(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
        const SizedBox(height: 8),
        Text(content, style: const TextStyle(
            fontSize: 14, color: Colors.black87, height: 1.5)),
      ]),
    );
  }
}
