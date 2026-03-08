import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:pdfx/pdfx.dart';
import 'package:internet_file/internet_file.dart';
import '../../../data/repositories/api_repository.dart';
import '../../../core/constants/app_colors.dart';

class MediaViewPage extends ConsumerStatefulWidget {
  final String type;
  const MediaViewPage({super.key, required this.type});

  @override
  ConsumerState<MediaViewPage> createState() => _MediaViewPageState();
}

class _MediaViewPageState extends ConsumerState<MediaViewPage> {
  YoutubePlayerController? _ytController;
  PdfController? _pdfController;
  bool _isLoadingPdf = false;
  bool _hasPdfError = false;

  void _initYoutube(String url) {
    if (_ytController != null) return;

    String videoId = '';
    if (url.contains('youtu.be/')) {
      videoId = url.split('youtu.be/')[1].split('?')[0];
    } else if (url.contains('youtube.com/watch')) {
      videoId = Uri.parse(url).queryParameters['v'] ?? '';
    }

    if (videoId.isNotEmpty) {
      _ytController = YoutubePlayerController(
        initialVideoId: videoId,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          loop: false,
          enableCaption: false,
        ),
      );
    }
  }

  void _initPdf(String url) async {
    if (_pdfController != null || _isLoadingPdf || _hasPdfError) return;

    // Future.microtask orqali build cycle dan keyin state o'zgarishini ta'minlaymiz
    Future.microtask(() => setState(() => _isLoadingPdf = true));

    final match = RegExp(r'[-\w]{25,}').firstMatch(url);
    if (match != null) {
      final fileId = match.group(0);
      final directUrl =
          'https://drive.googleusercontent.com/download?id=$fileId&export=download';

      try {
        _pdfController = PdfController(
          document: PdfDocument.openData(InternetFile.get(directUrl)),
        );
        if (mounted) setState(() => _isLoadingPdf = false);
      } catch (e) {
        if (mounted) {
          setState(() {
            _hasPdfError = true;
            _isLoadingPdf = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _hasPdfError = true;
          _isLoadingPdf = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _ytController?.close();
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(moduleDataProvider);
    if (data == null) return const Center(child: Text('Ma\'lumot yo\'q'));

    final url = widget.type == 'pdf' ? data.pdfUrl : data.videoUrl;
    if (url.isEmpty) return const Center(child: Text('Fayl kiritilmagan'));

    if (widget.type == 'video') {
      _initYoutube(url);
      return Column(
        children: [
          const SizedBox(height: 10),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(data.artikul,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18)),
                const Icon(Icons.video_library, color: AppColors.accent),
              ],
            ),
          ),
          Expanded(
            child: _ytController != null
                ? Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: YoutubePlayerIFrame(
                        controller: _ytController,
                        aspectRatio: 16 / 9,
                      ),
                    ),
                  )
                : const Center(child: Text('Noto\'g\'ri video URL')),
          ),
        ],
      );
    }

    // PDF View
    _initPdf(url);

    return Column(
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(data.artikul,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              const Icon(Icons.picture_as_pdf, color: AppColors.danger),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingPdf
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : _hasPdfError || _pdfController == null
                  ? const Center(
                      child: Text('Chizmani yuklashda xatolik yuz berdi.'))
                  : PdfView(
                      controller: _pdfController!,
                      scrollDirection: Axis.vertical,
                      pageSnapping: false,
                    ),
        ),
      ],
    );
  }
}
