import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/module_model.dart';

final historyProvider = StateNotifierProvider<HistoryNotifier, List<ModuleModel>>((ref) {
  return HistoryNotifier();
});

class HistoryNotifier extends StateNotifier<List<ModuleModel>> {
  HistoryNotifier() : super([]) {
    loadHistory();
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? saved = prefs.getStringList('scan_history');
    if (saved != null) {
      state = saved.map((item) => ModuleModel.fromJson(jsonDecode(item))).toList();
    }
  }

  Future<void> addEntry(ModuleModel module) async {
    if (module.artikul.isEmpty) return;
    
    final newState = List<ModuleModel>.from(state);
    newState.removeWhere((item) => item.artikul == module.artikul);
    newState.insert(0, module);
    
    if (newState.length > 20) newState.removeLast();
    
    state = newState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('scan_history', state.map((item) => jsonEncode(item.toJson())).toList());
  }
}
