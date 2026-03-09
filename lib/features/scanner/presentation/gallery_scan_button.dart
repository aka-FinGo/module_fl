import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Galereyadan rasm tanlash va QR/barcode scan qilish tugmasi.
/// 
/// Ishlating:
/// ```dart
/// GalleryScanButton(
///   onDetected: (code) => print('Topildi: $code'),
/// )
/// ```
class GalleryScanButton extends StatefulWidget {
  final void Function(String code) onDetected;
  final Widget? child;
  final String tooltip;

  const GalleryScanButton({
    super.key,
    required this.onDetected,
    this.child,
    this.tooltip = 'Rasmdan scan',
  });

  @override
  State<GalleryScanButton> createState() => _GalleryScanButtonState();
}

class _GalleryScanButtonState extends State<GalleryScanButton> {
  bool _isScanning = false;

  Future<void> _pickAndScan() async {
    if (_isScanning) return;

    // Galereyadan rasm tanlash
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100, // Siqmaslik — QR aniqligi uchun muhim
    );
    if (image == null) return;

    setState(() => _isScanning = true);

    try {
      // mobile_scanner bilan rasmni tahlil qilish
      final result = await MobileScannerController().analyzeImage(image.path);

      if (!mounted) return;

      if (result != null && result.barcodes.isNotEmpty) {
        final barcode = result.barcodes.first;
        final code = barcode.displayValue ?? barcode.rawValue;
        if (code != null && code.isNotEmpty) {
          widget.onDetected(code);
          return;
        }
      }

      // Hech narsa topilmadi
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR yoki barcode topilmadi'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Xatolik: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: IconButton(
        onPressed: _isScanning ? null : _pickAndScan,
        icon: _isScanning
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : widget.child ??
                const Icon(Icons.photo_library_outlined, color: Colors.white),
      ),
    );
  }
}