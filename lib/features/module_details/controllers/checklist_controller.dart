import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final checklistProvider = StateNotifierProvider<ChecklistNotifier, Set<String>>((ref) {
  return ChecklistNotifier();
});

class ChecklistNotifier extends StateNotifier<Set<String>> {
  ChecklistNotifier() : super({}) {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? saved = prefs.getStringList('checked_items');
    if (saved != null) {
      state = saved.toSet();
    }
  }

  void toggleItem(String uid) async {
    final newState = Set<String>.from(state);
    if (newState.contains(uid)) {
      newState.remove(uid);
    } else {
      newState.add(uid);
    }
    state = newState;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('checked_items', state.toList());
  }

  bool isChecked(String uid) => state.contains(uid);
}
