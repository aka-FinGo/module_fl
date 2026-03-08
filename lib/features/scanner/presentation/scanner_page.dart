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
  // Web uchun controller sozlamalari biroz yumshatildi
  late MobileScannerController controller;
  bool isDetected = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
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
    if (isDetected) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      setState(() { isDetected = true; });
      
      final String code = barcodes.first.rawValue!;
      // Webda kamerani to'xtatish ba'zida brauzerni qotirishi mumkin, 
      // shuning uchun avval navigatsiya qilamiz
      ref.read(scannedBarcodeProvider.notifier).state = code;
      ref.read(isLoadingProvider.notifier).state = true;
      
      _fetchData(code);
      
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Skaner', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: controller.torchState,
              builder: (context, state, child) {
                return Icon(
                  state == TorchState.on ? Icons.flash_on : Icons.flash_off,
                  color: state == TorchState.on ? AppColors.warning : Colors.white,
                );
              },
            ),
            onPressed: () => controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // SCANNER WIDGET
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off, color: Colors.white, size: 60),
                      const SizedBox(height: 16),
                      Text(
                        error.errorCode == MobileScannerErrorCode.permissionDenied
                            ? 'Kameraga ruxsat berilmagan! Brauzer sozlamalarini tekshiring.'
                            : 'Kamera xatosi: ${error.errorDetails?.message ?? "Noma'lum"}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Orqaga'),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
          // SCAN WINDOW (Kvadrat oyna)
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                children: [
                  // Burchaklardagi dekorativ chiziqlar
                  Positioned(top: 10, left: 10, child: _corner(0)),
                  Positioned(top: 10, right: 10, child: _corner(1)),
                  Positioned(bottom: 10, left: 10, child: _corner(2)),
                  Positioned(bottom: 10, right: 10, child: _corner(3)),
                ],
              ),
            ),
          ),
          // INFO TEXT
          const Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Barkod yoki QR kodni kvadratga joylang',
                style: TextStyle(color: Colors.white70, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _corner(int index) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        border: Border(
          top: index < 2 ? BorderSide(color: AppColors.accent, width: 4) : BorderSide.none,
          bottom: index >= 2 ? BorderSide(color: AppColors.accent, width: 4) : BorderSide.none,
          left: index % 2 == 0 ? BorderSide(color: AppColors.accent, width: 4) : BorderSide.none,
          right: index % 2 != 0 ? BorderSide(color: AppColors.accent, width: 4) : BorderSide.none,
        ),
      ),
    );
  }
}
