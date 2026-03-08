import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/api_repository.dart';
import '../../home/controllers/history_controller.dart';
import '../../shell/presentation/shell_page.dart';

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

      // Play beep sound
      try {
        await _player.play(UrlSource(
            'https://assets.mixkit.co/active_storage/sfx/2568/2568-preview.mp3'));
      } catch (e) {
        // Ignore playback errors
      }

      setState(() {
        _isProcessing = true;
      });

      // Riverpod holatlari — Scan boshlandi
      ref.read(scannedBarcodeProvider.notifier).state = code;
      ref.read(isLoadingProvider.notifier).state = true;
      ref.read(appBarTitleProvider.notifier).state = 'Yuklanmoqda...';

      // Avval API ni chaqiramiz, keyin sahifani yopamiz
      await _processScan(code);

      // API tugagandan KEYIN Furnitura tabiga o'tamiz va sahifani yopamiz
      if (mounted) {
        ref.read(bottomNavIndexProvider.notifier).state = 3;
        Navigator.pop(context);
      }
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

      // Tarixga saqlash
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
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, state, child) {
              final torchState = state.torchState;
              return IconButton(
                color: Colors.white,
                icon: Icon(
                  torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                ),
                onPressed: () => controller.toggleTorch(),
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
          // Skaner ramkasi (Overlay)
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
