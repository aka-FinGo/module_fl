import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/api_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/checklist_controller.dart';

// Faqat bitta kategoriya ochiq turishi uchun provayder
final expandedCategoryProvider = StateProvider<String?>((ref) => null);

class ModuleDetailsPage extends ConsumerWidget {
  const ModuleDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moduleData = ref.watch(moduleDataProvider);
    final isLoading = ref.watch(isLoadingProvider);
    final expandedCategory = ref.watch(expandedCategoryProvider);
    if (isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
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

    final categories = moduleData.furnituralar.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(top: 10),
      itemCount: categories.length + 1, // +1 Spacer uchun
      itemBuilder: (context, index) {
        if (index == categories.length) {
          return const SizedBox(height: 150); // Scroll Spacer
        }

        final category = categories[index];
        final items = moduleData.furnituralar[category] ?? [];
        final isExpanded = expandedCategory == category;

        return Column(
          children: [
            // ACCORDION HEADER
            GestureDetector(
              onTap: () {
                ref.read(expandedCategoryProvider.notifier).state =
                    isExpanded ? null : category;
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(category,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
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
            // ACCORDION BODY (Exclusive logic)
            if (isExpanded)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
                child: Column(
                  children: _buildSortedItems(
                      items, category, moduleData.artikul, ref),
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _buildSortedItems(
      List items, String category, String artikul, WidgetRef ref) {
    // Saralash: Belgilanganlar eng pastga tushadi
    final sortedItems = List.from(items);
    sortedItems.sort((a, b) {
      final aUid = "${artikul}_${category}_${items.indexOf(a)}";
      final bUid = "${artikul}_${category}_${items.indexOf(b)}";
      final aChecked = ref.read(checklistProvider).contains(aUid) ? 1 : 0;
      final bChecked = ref.read(checklistProvider).contains(bUid) ? 1 : 0;
      return aChecked.compareTo(bChecked);
    });

    return sortedItems.map((item) {
      final uid = "${artikul}_${category}_${items.indexOf(item)}";
      final isChecked = ref.read(checklistProvider).contains(uid);

      return InkWell(
        onTap: () => ref.read(checklistProvider.notifier).toggleItem(uid),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isChecked
                ? AppColors.accent.withOpacity(0.1)
                : Colors.transparent,
            border: const Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nomi,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          decoration:
                              isChecked ? TextDecoration.lineThrough : null,
                          color:
                              isChecked ? AppColors.accent : AppColors.textDark,
                        )),
                    Text(item.ulchov,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textGray)),
                  ],
                ),
              ),
              Text(item.soni,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isChecked ? AppColors.accent : AppColors.danger,
                  )),
            ],
          ),
        ),
      );
    }).toList();
  }
}
