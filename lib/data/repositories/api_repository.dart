import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/module_model.dart';

// API Manzili (Google Sheets AppScript Deploy URL)
const String apiUrl =
    'https://script.google.com/macros/s/AKfycbxyWSaRdn-4NZkkwJiAb2Q-uezsE8U_iFhjdSfsd4vZRHodaQ-aLhMNZe9ZwqjdVMjQ/exec';

// Global holat provayderlari
final scannedBarcodeProvider = StateProvider<String?>((ref) => null);
final moduleDataProvider = StateProvider<ModuleModel?>((ref) => null);
final isLoadingProvider = StateProvider<bool>((ref) => false);

final apiRepositoryProvider = Provider<ApiRepository>((ref) {
  return ApiRepository();
});

class ApiRepository {
  Future<ModuleModel> fetchModuleData(String barcode) async {
    try {
      final uri = Uri.parse(apiUrl).replace(
        queryParameters: {'barcode': barcode},
      );

      // http package Google AppScript redirect (302) ni avtomatik kuzatadi
      final response = await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final body = response.body.trim();

        // JSON bo'lmagan HTML javob kelishi mumkin (AppScript xatosi)
        if (!body.startsWith('{') && !body.startsWith('[')) {
          return ModuleModel(
            artikul: '',
            nomi: '',
            pdfUrl: '',
            videoUrl: '',
            furnituralar: {},
            error:
                'Serverdan noto\'g\'ri javob keldi. AppScript "Deploy" sozlamalarini tekshiring.',
          );
        }

        final Map<String, dynamic> jsonData = jsonDecode(body);
        return ModuleModel.fromJson(jsonData);
      } else {
        return ModuleModel(
          artikul: '',
          nomi: '',
          pdfUrl: '',
          videoUrl: '',
          furnituralar: {},
          error: 'Server xatosi: ${response.statusCode}',
        );
      }
    } on FormatException {
      return ModuleModel(
        artikul: '',
        nomi: '',
        pdfUrl: '',
        videoUrl: '',
        furnituralar: {},
        error: 'JSON parse xatosi. AppScript javobini tekshiring.',
      );
    } catch (e) {
      String errorMessage = 'Tarmoq xatosi! Internetni tekshiring.';
      if (e.toString().contains('TimeoutException')) {
        errorMessage = 'Ulanish vaqti tugadi (20s). Internetni tekshiring.';
      }
      return ModuleModel(
        artikul: '',
        nomi: '',
        pdfUrl: '',
        videoUrl: '',
        furnituralar: {},
        error: errorMessage,
      );
    }
  }
}
