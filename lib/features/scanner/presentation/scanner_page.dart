import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/api_repository.dart';

class ScannerPage extends ConsumerStatefulWidget {
  const ScannerPage({super.key});

  @override
  ConsumerState<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends ConsumerState<ScannerPage> {
  late MobileScannerController controller;
  bool isDetected = false;

  @override
  void initState() {
    super.initState();
    // Chiziqli barkodlar va avtofokus formati
    controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
      formats: const [
        BarcodeFormat.qrCode,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
      ],
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (isDetected) return; // Ikki marta o'qib yuborishdan himoya
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      setState(() {
        isDetected = true;
      });
      
      final String code = barcodes.first.rawValue!;
      controller.stop(); // Kamerani to'xtatish
      
      // Riverpod orqali global holatni yangilash
      ref.read(scannedBarcodeProvider.notifier).state = code;
      ref.read(isLoadingProvider.notifier).state = true;
      
      // API ga so'rov yuborish mantiqi (Asinxron)
      _fetchData(code);
      
      // Skaner sahifasidan orqaga (Asosiy Qobiqqa) qaytish
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _fetchData(String barcode) async {
    final apiRepo = ref.read(apiRepositoryProvider);
    final data = await apiRepo.fetchModuleData(barcode);
    ref.read(moduleDataProvider.notifier).state = data;
    ref.read(isLoadingProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kamerani yo\'naltiring', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: controller.torchState,
              builder: (context, state, child) {
                switch (state) {
                  case TorchState.off:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: AppColors.warning);
                }
              },
            ),
            onPressed: () => controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
          ),
          // Skaner oynasi (Kvadrat shakl)
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Pastki ma'lumot matni
          const Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              'Barkod yoki QR kodni kvadrat ichiga oling',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14, backgroundColor: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
