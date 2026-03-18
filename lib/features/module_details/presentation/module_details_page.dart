import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/api_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/checklist_controller.dart';

final expandedCategoryProvider = StateProvider<String?>((ref) => null);

class ModuleDetailsPage extends ConsumerWidget {
  const ModuleDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moduleData      = ref.watch(moduleDataProvider);
    final isLoading       = ref.watch(isLoadingProvider);
    final expandedCat     = ref.watch(expandedCategoryProvider);
    final checkedItems    = ref.watch(checklistProvider);

    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    if (moduleData == null) {
      return const Center(
        child: Text('Hali modul skaner qilinmadi',
            style: TextStyle(color: AppColors.textGray, fontSize: 16)),
      );
    }

    if (moduleData.error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(moduleData.error,
              style: const TextStyle(
                  color: AppColors.danger, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
        ),
      );
    }

    if (moduleData.furnituralar.isEmpty) {
      return const Center(
        child: Text('Furnituralar kiritilmagan',
            style: TextStyle(color: AppColors.textGray, fontSize: 15)),
      );
    }

    final categories = moduleData.furnituralar.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(top: 10, bottom: 150),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category  = categories[index];
        final items     = moduleData.furnituralar[category] ?? [];
        final isExpanded = expandedCat == category;

        // Indeksni saqlash uchun original indeks bilan birgalikda ishlaymiz
        final indexedItems = List.generate(items.length, (i) => (i, items[i]));

        // Saralash: belgilanganlar pastga
        indexedItems.sort((a, b) {
          final aUid = '${moduleData.artikul}_${category}_${a.$1}';
          final bUid = '${moduleData.artikul}_${category}_${b.$1}';
          return (checkedItems.contains(aUid) ? 1 : 0)
              .compareTo(checkedItems.contains(bUid) ? 1 : 0);
        });

        // Belgilanmagan va belgilangan sonlari
        final uncheckedCount = indexedItems
            .where((e) => !checkedItems.contains('${moduleData.artikul}_${category}_${e.$1}'))
            .length;

        return Column(
          children: [
            // ── ACCORDION HEADER ──────────────────────────
            GestureDetector(
              onTap: () {
                ref.read(expandedCategoryProvider.notifier).state =
                    isExpanded ? null : category;
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(category,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    if (checkedItems.any((uid) =>
                        uid.startsWith('${moduleData.artikul}_${category}_')))
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$uncheckedCount/${items.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),

            // ── ACCORDION BODY ────────────────────────────
            if (isExpanded)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
                child: Column(
                  children: indexedItems.map((entry) {
                    final originalIndex = entry.$1;
                    final item          = entry.$2;
                    // UID — original index bilan (sorted emas!)
                    final uid      = '${moduleData.artikul}_${category}_$originalIndex';
                    final isChecked = checkedItems.contains(uid);

                    return InkWell(
                      onTap: () =>
                          ref.read(checklistProvider.notifier).toggleItem(uid),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isChecked
                              ? AppColors.accent.withOpacity(0.08)
                              : Colors.transparent,
                          border: const Border(
                              bottom: BorderSide(color: Color(0xFFEEEEEE))),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isChecked
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: isChecked ? AppColors.accent : AppColors.textGray,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.nomi,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        decoration: isChecked
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: isChecked
                                            ? AppColors.textGray
                                            : AppColors.textDark,
                                      )),
                                  if (item.ulchov.isNotEmpty)
                                    Text(item.ulchov,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textGray)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isChecked
                                    ? AppColors.accent.withOpacity(0.1)
                                    : AppColors.danger.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(item.soni,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isChecked
                                        ? AppColors.accent
                                        : AppColors.danger,
                                  )),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}
