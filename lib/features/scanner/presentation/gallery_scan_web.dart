// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:async';
import 'package:flutter/material.dart';

Future<void> scanFromGallery({
  required BuildContext context,
  required void Function(String code) onDetected,
}) async {
  final completer = Completer<String?>();

  // File input element yaratish
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..style.display = 'none';
  html.document.body!.append(input);

  input.onChange.listen((event) async {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      input.remove();
      return;
    }

    final file = files[0];
    final reader = html.FileReader();
    reader.readAsDataUrl(file);

    reader.onLoad.listen((_) {
      final dataUrl = reader.result as String;
      _decodeQrFromDataUrl(dataUrl, completer);
      input.remove();
    });

    reader.onError.listen((_) {
      completer.complete(null);
      input.remove();
    });
  });

  // Bekor qilinsa
  input.onBlur.listen((_) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!completer.isCompleted) completer.complete(null);
    });
  });

  input.click();

  final code = await completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () => null,
  );

  if (code != null && code.isNotEmpty) {
    onDetected(code);
  } else if (code == null) {
    // Foydalanuvchi bekor qildi yoki topilmadi — tekshiramiz
    // (completer null = bekor qilindi, '' = topilmadi)
  } else {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR yoki barcode topilmadi'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

void _decodeQrFromDataUrl(String dataUrl, Completer<String?> completer) {
  // Canvas orqali rasm o'lchamini olib, jsQR bilan tahlil qilish
  final img = html.ImageElement()..src = dataUrl;

  img.onLoad.listen((_) {
    final canvas = html.CanvasElement(
      width: img.naturalWidth,
      height: img.naturalHeight,
    );
    final ctx = canvas.context2D;
    ctx.drawImage(img, 0, 0);

    final imageData = ctx.getImageData(0, 0, canvas.width!, canvas.height!);

    try {
      // jsQR — web/index.html da yuklangan
      final result = js.context.callMethod('jsQR', [
        imageData.data,
        canvas.width,
        canvas.height,
        js.JsObject.jsify({'inversionAttempts': 'attemptBoth'}),
      ]);

      if (result != null) {
        final data = result['data'] as String?;
        if (data != null && data.isNotEmpty) {
          completer.complete(data);
          return;
        }
      }
      completer.complete(''); // Topilmadi
    } catch (e) {
      completer.complete(''); // jsQR mavjud emas yoki xato
    }
  });

  img.onError.listen((_) => completer.complete(null));
}