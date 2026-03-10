import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

Future<void> scanFromGallery({
  required BuildContext context,
  required void Function(String code) onDetected,
}) async {
  final picker = ImagePicker();
  final XFile? image = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 100,
  );
  if (image == null) return;

  try {
    final controller = MobileScannerController();
    final result = await controller.analyzeImage(image.path);
    await controller.dispose();

    if (result != null && result.barcodes.isNotEmpty) {
      final barcode = result.barcodes.first;
      final code = barcode.displayValue ?? barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        onDetected(code);
        return;
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR yoki barcode topilmadi'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Xatolik: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}