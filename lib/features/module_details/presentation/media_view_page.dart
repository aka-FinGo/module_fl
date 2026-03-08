import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import '../../../data/repositories/api_repository.dart';
import '../../../core/constants/app_colors.dart';
import 'web_iframe_stub.dart' if (dart.library.html) 'web_iframe.dart';

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
  final bool _isWeb =
      const bool.fromEnvironment('dart.library.html', defaultValue: false);

  void _initYoutube(String url) {
    if (_ytController != null || _isWeb) return;

    final videoId = YoutubePlayer.convertUrlToId(url);
    if (videoId != null) {
      _ytController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
          enableCaption: false,
          disableDragSeek: false,
        ),
      );
    }
  }

  void _initPdf(String url) async {
    if (_pdfController != null || _isLoadingPdf || _hasPdfError || _isWeb)
      return;

    Future.microtask(() => setState(() => _isLoadingPdf = true));

    final match = RegExp(r'[-\w]{25,}').firstMatch(url);
    if (match != null) {
      final fileId = match.group(0);
      final directUrl =
          'https://drive.googleusercontent.com/download?id=$fileId&export=download';

      try {
        final response = await http.get(Uri.parse(directUrl));
        if (response.statusCode == 200) {
          _pdfController = PdfController(
            document: PdfDocument.openData(response.bodyBytes),
          );
          if (mounted) setState(() => _isLoadingPdf = false);
        } else {
          throw Exception('PFFFailed');
        }
      } catch (e) {
        if (mounted)
          setState(() {
            _hasPdfError = true;
            _isLoadingPdf = false;
          });
      }
    } else {
      if (mounted)
        setState(() {
          _hasPdfError = true;
          _isLoadingPdf = false;
        });
    }
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sikani ochib bo\'lmadi')),
        );
      }
    }
  }

  String _getIframeUrl(String originalUrl, bool isVideo) {
    if (isVideo) {
      String vidId = "";
      if (originalUrl.contains("youtu.be/")) {
        vidId = originalUrl.split("youtu.be/")[1].split("?")[0];
      } else if (originalUrl.contains("youtube.com/watch")) {
        vidId = Uri.parse(originalUrl).queryParameters['v'] ?? "";
      }
      return 'https://www.youtube.com/embed/$vidId?modestbranding=1&rel=0&controls=1&fs=0&iv_load_policy=3';
    }

    final match = RegExp(r'[-\w]{25,}').firstMatch(originalUrl);
    if (match != null) {
      final fileId = match.group(0);
      return 'https://drive.google.com/file/d/$fileId/preview';
    }
    return originalUrl;
  }

  @override
  void initState() {
    super.initState();
    if (_isWeb && widget.type == 'pdf') {
      setWebZoomable(true);
    }
  }

  @override
  void dispose() {
    _ytController?.dispose();
    _pdfController?.dispose();
    if (_isWeb && widget.type == 'pdf') {
      setWebZoomable(false);
    }
    super.dispose();
  }

  double _pdfScale = 1.0;

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
            child: _isWeb
                ? Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: buildWebIframe(_getIframeUrl(url, true), true,
                          key: ValueKey('vid_${data.artikul}')),
                    ),
                  )
                : _ytController != null
                    ? Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: YoutubePlayer(
                            controller: _ytController!,
                            showVideoProgressIndicator: true,
                            progressIndicatorColor: AppColors.accent,
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
          child: Stack(
            children: [
              InteractiveViewer(
                maxScale: 5.0,
                minScale: 0.5,
                child: Center(
                  child: Transform.scale(
                    scale: _pdfScale,
                    child: _isWeb
                        ? buildWebIframe(_getIframeUrl(url, false), false,
                            key: ValueKey('pdf_${data.artikul}'))
                        : _isLoadingPdf
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.accent))
                            : _hasPdfError || _pdfController == null
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.error_outline,
                                            size: 48,
                                            color: AppColors.textGray),
                                        const SizedBox(height: 16),
                                        const Text(
                                            'Chizmani ilova ichida yuklashda xatolik yuz berdi.'),
                                        const SizedBox(height: 16),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.primary,
                                              foregroundColor: Colors.white),
                                          onPressed: () => _launchURL(url),
                                          icon: const Icon(Icons.open_in_new),
                                          label: const Text('Brauzerda ochish'),
                                        ),
                                      ],
                                    ),
                                  )
                                : PdfView(
                                    controller: _pdfController!,
                                    scrollDirection: Axis.vertical,
                                    pageSnapping: false,
                                  ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'zoom_in',
                      onPressed: () => setState(() => _pdfScale += 0.25),
                      backgroundColor: AppColors.primary,
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'zoom_out',
                      onPressed: () => setState(() {
                        if (_pdfScale > 0.5) _pdfScale -= 0.25;
                      }),
                      backgroundColor: AppColors.primary,
                      child: const Icon(Icons.remove, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'zoom_reset',
                      onPressed: () => setState(() => _pdfScale = 1.0),
                      backgroundColor: Colors.white,
                      child:
                          const Icon(Icons.refresh, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
