import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/module_model.dart';

// ─── Apps Script URL ─────────────────────────────────────────
// Bu URL Apps Script'dan olinadi (Deploy > Web App URL)
const String apiUrl =
    'https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec';

// ─── Providers ───────────────────────────────────────────────
final scannedBarcodeProvider = StateProvider<String?>((ref) => null);
final moduleDataProvider     = StateProvider<ModuleModel?>((ref) => null);
final isLoadingProvider      = StateProvider<bool>((ref) => false);

final apiRepositoryProvider = Provider<ApiRepository>((ref) {
  return ApiRepository();
});

// ─── Cache: Telegram URL larini vaqtincha saqlash ────────────
// (getFile har chaqiriqda network ishlatadi, shuning uchun kesh)
final _urlCache = <String, _CachedUrl>{};

class _CachedUrl {
  final String url;
  final DateTime expiresAt;
  _CachedUrl(this.url, this.expiresAt);
  bool get isValid => DateTime.now().isBefore(expiresAt);
}

// ─────────────────────────────────────────────────────────────
class ApiRepository {
  // ── Worker: barcode scan ───────────────────────────────────
  Future<ModuleModel> fetchModuleData(String barcode) async {
    try {
      final uri = Uri.parse(apiUrl).replace(
        queryParameters: {'barcode': barcode},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final body = response.body.trim();
        if (!body.startsWith('{') && !body.startsWith('[')) {
          return _error('Serverdan noto\'g\'ri javob keldi');
        }
        return ModuleModel.fromJson(jsonDecode(body));
      }
      return _error('Server xatosi: ${response.statusCode}');
    } catch (e) {
      final msg = e.toString().contains('TimeoutException')
          ? 'Ulanish vaqti tugadi. Internetni tekshiring.'
          : 'Tarmoq xatosi! Internetni tekshiring.';
      return _error(msg);
    }
  }

  // ── Telegram file URL ni olish (Apps Script proxy orqali) ──
  // file_id → Apps Script → Telegram getFile → download URL
  Future<String?> getTelegramFileUrl(String fileId) async {
    if (fileId.isEmpty) return null;

    // Keshdan tekshirish
    final cached = _urlCache[fileId];
    if (cached != null && cached.isValid) return cached.url;

    try {
      final uri = Uri.parse(apiUrl).replace(
        queryParameters: {'action': 'file', 'id': fileId},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final url  = data['url'] as String?;
      if (url == null || url.isEmpty) return null;

      // 50 daqiqaga keshda saqlash (Telegram URL lari 1 soat amal qiladi)
      _urlCache[fileId] = _CachedUrl(url, DateTime.now().add(const Duration(minutes: 50)));
      return url;
    } catch (_) {
      return null;
    }
  }

  ModuleModel _error(String msg) => ModuleModel(
    artikul: '', nomi: '', pdfUrl: '', videoUrl: '',
    tgPdfId: '', tgVideoId: '', furnituralar: {}, error: msg,
  );
}
