import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class OfflineCacheManager {
  static const String key = 'pdf_cache';

  static final DefaultCacheManager _cacheManager = DefaultCacheManager();

  /// PDF faylni keshga tushiradi yoki mavjud bo'lsa uni qaytaradi
  static Future<File?> getCachedPdf(String url) async {
    try {
      final fileInfo = await _cacheManager.getFileFromCache(url);
      if (fileInfo != null) {
        return fileInfo.file;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// PDF faylni fon rejimida yuklab oladi
  static Future<void> downloadToCache(String url) async {
    try {
      await _cacheManager.downloadFile(url, key: url);
    } catch (e) {
      // Xatolik bo'lsa indamaymiz
    }
  }

  /// Keshni tozalash (ixtiyoriy)
  static Future<void> clearCache() async {
    await _cacheManager.emptyCache();
  }
}
