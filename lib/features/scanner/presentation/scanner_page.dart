import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/api_repository.dart';
import '../../shell/presentation/shell_page.dart';

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
    controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
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
      final String code = barcodes.first.rawValue!;
      
      setState(() {
        isDetected = true;
      });

      // 1. Kamerani darhol muzlatish (Qotib qolmaslik uchun)
      controller.stop();
      
      // 2. Navigatsiya va Sarlavha holatlarini yangilash
      ref.read(bottomNavIndexProvider.notifier).state = 1;
      ref.read(appBarTitleProvider.notifier).state = 'Artikul: $code';
      ref.read(scannedBarcodeProvider.notifier).state = code;
      ref.read(isLoadingProvider.notifier).state = true;
      
      // 3. API so'rovini fonda boshlash
      _fetchData(code);
      
      // 4. Skaner oynasidan chiqish
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _fetchData(String barcode) async {
    final apiRepo = ref.read(apiRepositoryProvider);
    final data = await apiRepo.fetchModuleData(barcode);
    ref.read(moduleDataProvider.notifier).state = data;
    ref.read(isLoadingProvider.notifier).state = false;
    
    // Agar xato bo'lsa, sarlavhani xatoga moslash
    if (data.error.isNotEmpty) {
      ref.read(appBarTitleProvider.notifier).state = 'Xatolik yuz berdi';
    } else {
      ref.read(appBarTitleProvider.notifier).state = 'Modul: ${data.artikul}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Skanerlash', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
          ),
          // Skaner ramkasi
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 3),
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
          // Yuklanish holati overlay
          if (isDetected)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.accent),
                    SizedBox(height: 16),
                    Text('Ma\'lumotlar yuklanmoqda...', 
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
