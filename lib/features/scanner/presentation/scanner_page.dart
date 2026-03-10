import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/api_repository.dart';
import '../../home/controllers/history_controller.dart';
import '../../shell/presentation/shell_page.dart';
import 'gallery_scan_button.dart';

class ScannerPage extends ConsumerStatefulWidget {
  const ScannerPage({super.key});

  @override
  ConsumerState<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends ConsumerState<ScannerPage> {
  late MobileScannerController controller;
  bool _isProcessing = false;
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
      formats: [
        BarcodeFormat.qrCode,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.ean13,
      ],
    );
  }

  @override
  void dispose() {
    controller.dispose();
    _player.dispose();
    super.dispose();
  }

  void _handleCapture(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      final String code = barcodes.first.rawValue!;
      await _processCode(code);
    }
  }

  /// Kamera yoki galereyadan kelgan barcode ni qayta ishlash
  Future<void> _processCode(String code) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Kamerani to'xtatish
    try { await controller.stop(); } catch (_) {}

    // Beep
    try {
      await _player.play(UrlSource(
          'https://assets.mixkit.co/active_storage/sfx/2568/2568-preview.mp3'))
          .timeout(const Duration(seconds: 2));
    } catch (_) {}

    ref.read(scannedBarcodeProvider.notifier).state = code;
    ref.read(isLoadingProvider.notifier).state = true;
    ref.read(appBarTitleProvider.notifier).state = 'Yuklanmoqda...';

    await _processScan(code);

    if (mounted) {
      ref.read(bottomNavIndexProvider.notifier).state = 3;
      Navigator.pop(context);
    }
  }

  Future<void> _processScan(String code) async {
    try {
      final apiRepo = ref.read(apiRepositoryProvider);
      final data = await apiRepo.fetchModuleData(code);
      ref.read(moduleDataProvider.notifier).state = data;
      ref.read(isLoadingProvider.notifier).state = false;
      ref.read(appBarTitleProvider.notifier).state =
          data.error.isNotEmpty ? 'Xato!' : 'Modul: ${data.artikul}';
      if (data.artikul.isNotEmpty) {
        ref.read(historyProvider.notifier).addEntry(data);
      }
    } catch (e) {
      ref.read(isLoadingProvider.notifier).state = false;
      ref.read(appBarTitleProvider.notifier).state = 'Xato yuz berdi';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Barkodni o\'qing',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Galereyadan rasm scan qilish
          GalleryScanButton(
            tooltip: 'Rasmdan scan',
            onDetected: (code) => _processCode(code),
          ),
          // Chiroq
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, state, child) {
              if (!state.isInitialized) return const SizedBox.shrink();
              final torchState = state.torchState;
              return IconButton(
                color: Colors.white,
                icon: Icon(
                  torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                  color: torchState == TorchState.unavailable
                      ? Colors.grey
                      : Colors.white,
                ),
                onPressed: torchState == TorchState.unavailable
                    ? null
                    : () async {
                        try {
                          await controller.toggleTorch();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Fonarni yoqib bo\'lmadi')),
                            );
                          }
                        }
                      },
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _handleCapture,
          ),
          // Skaner ramkasi
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_isProcessing)
            const Center(
                child: CircularProgressIndicator(color: AppColors.accent)),
        ],
      ),
    );
  }
}