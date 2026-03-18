class FurnituraItem {
  final String nomi;
  final String ulchov;
  final String soni;

  FurnituraItem({required this.nomi, required this.ulchov, required this.soni});

  Map<String, dynamic> toJson() => {'nomi': nomi, 'ulchov': ulchov, 'soni': soni};

  factory FurnituraItem.fromJson(Map<String, dynamic> json) {
    return FurnituraItem(
      nomi: json['nomi']?.toString() ?? '',
      ulchov: json['ulchov']?.toString() ?? '',
      soni: json['soni']?.toString() ?? '',
    );
  }
}

class ModuleModel {
  final String artikul;
  final String nomi;
  final String pdfUrl;       // Google Drive URL (zaxira)
  final String videoUrl;     // YouTube/Drive URL (zaxira)
  final String tgPdfId;      // Telegram file_id (asosiy)
  final String tgVideoId;    // Telegram file_id (asosiy)
  final Map<String, List<FurnituraItem>> furnituralar;
  final String error;

  ModuleModel({
    required this.artikul,
    required this.nomi,
    required this.pdfUrl,
    required this.videoUrl,
    required this.tgPdfId,
    required this.tgVideoId,
    required this.furnituralar,
    required this.error,
  });

  /// PDF uchun eng yaxshi manba bor-yo'qligini tekshirish
  bool get hasPdf => tgPdfId.isNotEmpty || pdfUrl.isNotEmpty;

  /// Video uchun eng yaxshi manba bor-yo'qligini tekshirish
  bool get hasVideo => tgVideoId.isNotEmpty || videoUrl.isNotEmpty;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> fursJson = {};
    furnituralar.forEach((key, value) {
      fursJson[key] = value.map((v) => v.toJson()).toList();
    });
    return {
      'artikul': artikul,
      'nomi': nomi,
      'pdfUrl': pdfUrl,
      'videoUrl': videoUrl,
      'tgPdfId': tgPdfId,
      'tgVideoId': tgVideoId,
      'furnituralar': fursJson,
      'error': error,
    };
  }

  factory ModuleModel.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('error') && json['error'] != null && json['error'] != '') {
      return ModuleModel(
        artikul: '', nomi: '', pdfUrl: '', videoUrl: '',
        tgPdfId: '', tgVideoId: '',
        furnituralar: {}, error: json['error'].toString(),
      );
    }

    Map<String, List<FurnituraItem>> parsedFurnituralar = {};
    final fursRaw = json['furnituralar'];
    if (fursRaw != null && fursRaw is Map) {
      fursRaw.forEach((key, value) {
        if (value is List) {
          parsedFurnituralar[key.toString()] =
              value.map((item) => FurnituraItem.fromJson(item as Map<String, dynamic>)).toList();
        }
      });
    }

    return ModuleModel(
      artikul:     json['artikul']?.toString() ?? '',
      nomi:        json['nomi']?.toString() ?? '',
      pdfUrl:      json['pdfUrl']?.toString() ?? '',
      videoUrl:    json['videoUrl']?.toString() ?? '',
      tgPdfId:     json['tgPdfId']?.toString() ?? '',
      tgVideoId:   json['tgVideoId']?.toString() ?? '',
      furnituralar: parsedFurnituralar,
      error: '',
    );
  }
}
