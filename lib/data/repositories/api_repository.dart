import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/module_model.dart';

// API Manzili (O'zingizning Google Sheets Deploy URL manzilingizni shu yerga qo'ying)
const String apiUrl =
    'https://script.google.com/macros/s/AKfycbxyWSaRdn-4NZkkwJiAb2Q-uezsE8U_iFhjdSfsd4vZRHodaQ-aLhMNZe9ZwqjdVMjQ/exec';

// Global holat provayderlari
final scannedBarcodeProvider = StateProvider<String?>((ref) => null);
final moduleDataProvider = StateProvider<ModuleModel?>((ref) => null);
final isLoadingProvider = StateProvider<bool>((ref) => false);

final apiRepositoryProvider = Provider<ApiRepository>((ref) {
  return ApiRepository(Dio());
});

class ApiRepository {
  final Dio _dio;

  ApiRepository(this._dio) {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
  }

  Future<ModuleModel> fetchModuleData(String barcode) async {
    try {
      final response = await _dio.get(
        apiUrl,
        queryParameters: {'barcode': barcode},
      );

      if (response.statusCode == 200) {
        // String kelsa, uni JSON (Map) ga parse qilish
        final dynamic responseData = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;

        return ModuleModel.fromJson(responseData as Map<String, dynamic>);
      } else {
        return ModuleModel(
            artikul: '',
            nomi: '',
            pdfUrl: '',
            videoUrl: '',
            furnituralar: {},
            error: 'Server xatosi: ${response.statusCode}');
      }
    } on DioException catch (e) {
      String errorMessage = 'Tarmoq xatosi yoki CORS muammosi!';
      if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = 'Ulanish vaqti tugadi. Internetni tekshiring.';
      }
      return ModuleModel(
          artikul: '',
          nomi: '',
          pdfUrl: '',
          videoUrl: '',
          furnituralar: {},
          error: errorMessage);
    } catch (e) {
      return ModuleModel(
          artikul: '',
          nomi: '',
          pdfUrl: '',
          videoUrl: '',
          furnituralar: {},
          error: 'Noma\'lum xato: $e');
    }
  }
}
