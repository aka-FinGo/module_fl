import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/api_repository.dart';
import '../../../core/constants/app_colors.dart';

class ModuleDetailsPage extends ConsumerWidget {
  const ModuleDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moduleData = ref.watch(moduleDataProvider);
    final isLoading = ref.watch(isLoadingProvider);

    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    if (moduleData == null) {
      return const Center(
        child: Text('Hali modul skaner qilinmadi', style: TextStyle(color: AppColors.textGray)),
      );
    }

    if (moduleData.error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(moduleData.error, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
        ),
      );
    }

    return Center(
      child: Text('Artikul: ${moduleData.artikul}\nNomi: ${moduleData.nomi}', textAlign: TextAlign.center),
    );
  }
}
