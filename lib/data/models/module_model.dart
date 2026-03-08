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
  final String pdfUrl;
  final String videoUrl;
  final Map<String, List<FurnituraItem>> furnituralar;
  final String error;

  ModuleModel({
    required this.artikul,
    required this.nomi,
    required this.pdfUrl,
    required this.videoUrl,
    required this.furnituralar,
    required this.error,
  });

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
      'furnituralar': fursJson,
      'error': error,
    };
  }

  factory ModuleModel.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('error') && json['error'] != null && json['error'] != "") {
      return ModuleModel(artikul: '', nomi: '', pdfUrl: '', videoUrl: '', furnituralar: {}, error: json['error'].toString());
    }

    Map<String, List<FurnituraItem>> parsedFurnituralar = {};
    if (json['furnituralar'] != null) {
      Map<String, dynamic> fursJson = json['furnituralar'];
      fursJson.forEach((key, value) {
        List<dynamic> listData = value;
        parsedFurnituralar[key] = listData.map((item) => FurnituraItem.fromJson(item)).toList();
      });
    }

    return ModuleModel(
      artikul: json['artikul']?.toString() ?? '',
      nomi: json['nomi']?.toString() ?? '',
      pdfUrl: json['pdfUrl']?.toString() ?? '',
      videoUrl: json['videoUrl']?.toString() ?? '',
      furnituralar: parsedFurnituralar,
      error: '',
    );
  }
}
