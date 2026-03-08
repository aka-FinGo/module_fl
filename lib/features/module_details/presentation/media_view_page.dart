import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/api_repository.dart';
import '../../../core/constants/app_colors.dart';

class MediaViewPage extends ConsumerWidget {
  final String type;
  const MediaViewPage({super.key, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(moduleDataProvider);

    if (data == null) {
      return const Center(child: Text('Modul tanlanmagan', style: TextStyle(color: AppColors.textGray)));
    }

    final url = type == 'pdf' ? data.pdfUrl : data.videoUrl;

    if (url.isEmpty) {
      return Center(child: Text('${type == 'pdf' ? 'Chizma' : 'Video'} mavjud emas', style: const TextStyle(color: AppColors.danger)));
    }

    // PWA uchun Google Drive/YouTube ni ko'rsatuvchi sodda interfeys
    return Column(
      children: [
        const SizedBox(height: 20),
        Icon(type == 'pdf' ? Icons.picture_as_pdf : Icons.play_circle_filled, size: 80, color: AppColors.primary),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Artikul: ${data.artikul}\n\n${type == 'pdf' ? 'Chizmani ko\'rish uchun pastdagi tugmani bosing.' : 'Yig\'ish videosini tomosha qiling.'}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              // Kelajakda url_launcher qo'shiladi
            },
            icon: const Icon(Icons.open_in_new),
            label: Text('${type == 'pdf' ? 'Chizmani' : 'Videoni'} ochish'),
          ),
        ),
        const SizedBox(height: 100),
      ],
    );
  }
}
