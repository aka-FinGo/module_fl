import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MediaPdfHelper {
  static String extractDriveId(String url) =>
      RegExp(r'[-\w]{25,}').firstMatch(url)?.group(0) ?? '';

  static String buildDrivePreviewUrl(String url) {
    final id = extractDriveId(url);
    return id.isNotEmpty ? 'https://drive.google.com/file/d/$id/preview' : url;
  }

  static String buildDriveDownloadUrl(String url) {
    final id = extractDriveId(url);
    return id.isNotEmpty
        ? 'https://drive.google.com/uc?export=download&confirm=t&id=$id'
        : url;
  }

  static Future<File> getCacheFile(String url) async {
    final dir = await getTemporaryDirectory();
    final id = extractDriveId(url);
    final name = id.isNotEmpty ? 'pdf_$id.pdf' : 'pdf_cache.pdf';
    return File('${dir.path}/$name');
  }

  /// Drive virus-scan bypass bilan PDF yuklab olish.
  /// PDF bytes signature tekshiruvi: %PDF (0x25 0x50 0x44 0x46)
  static Future<bool> downloadPdf(String url, File file) async {
    try {
      var res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      final ct = res.headers['content-type'] ?? '';

      if (ct.contains('text/html')) {
        final body = res.body;
        final uuidM = RegExp(r'uuid=([^&>\s]+)').firstMatch(body);
        final confM = RegExp(r'confirm=([^&>\s]+)').firstMatch(body);
        final actM = RegExp(r'action="([^"]+)"').firstMatch(body);

        String newUrl = url;
        if (uuidM != null) {
          newUrl = '$url&uuid=${uuidM.group(1)}';
        } else if (confM != null && confM.group(1) != 't') {
          newUrl = '$url&confirm=${confM.group(1)}';
        } else if (actM != null) {
          newUrl = actM.group(1)!.replaceAll('&amp;', '&');
        }
        if (newUrl != url) {
          res = await http.get(Uri.parse(newUrl)).timeout(const Duration(seconds: 60));
        }
      }

      if (res.statusCode == 200 && res.bodyBytes.length > 1024) {
        final b = res.bodyBytes;
        if (b.length >= 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) {
          await file.writeAsBytes(b);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }
}