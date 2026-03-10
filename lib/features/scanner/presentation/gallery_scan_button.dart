import 'package:flutter/material.dart';
import 'gallery_scan_stub.dart'
    if (dart.library.html) 'gallery_scan_web.dart'
    if (dart.library.io) 'gallery_scan_mobile.dart';

/// Galereyadan rasm tanlash va QR/barcode scan qilish tugmasi.
/// Web va Mobile uchun alohida implementatsiya.
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
    setState(() => _isScanning = true);
    try {
      await scanFromGallery(
        context: context,
        onDetected: widget.onDetected,
      );
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