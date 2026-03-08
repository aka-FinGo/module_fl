import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import '../../../data/repositories/api_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../shell/presentation/shell_page.dart';
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
  final TransformationController _transformationController =
      TransformationController();
  bool _isLoadingPdf = false;
  bool _hasPdfError = false;
  bool _isFullScreen = false;
  int _currentPage = 1;
  int _totalPages = 0;
  final bool _isWeb =
      const bool.fromEnvironment('dart.library.html', defaultValue: false);

  void _toggleFullScreen() {
    _resetZoom();
    setState(() {
      _isFullScreen = !_isFullScreen;
      ref.read(isFullScreenProvider.notifier).state = _isFullScreen;
      if (_isFullScreen) {
        if (widget.type == 'video') {
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
  }

  void _zoom(double factor) {
    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final newScale = (currentScale * factor).clamp(0.5, 5.0);
    final ratio = newScale / currentScale;

    matrix.scale(ratio);
    _transformationController.value = matrix;
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

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
          final doc = await PdfDocument.openData(response.bodyBytes);
          _pdfController = PdfController(
            document: Future.value(doc),
          );
          if (mounted) {
            setState(() {
              _isLoadingPdf = false;
              _totalPages = doc.pagesCount;
            });
          }
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
    _transformationController.dispose();
    if (_isWeb && widget.type == 'pdf') {
      setWebZoomable(false);
    }
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreen) {
      return _buildFullScreenView();
    }

    final data = ref.watch(moduleDataProvider);
    if (data == null) return const Center(child: Text('Ma\'lumot yo\'q'));

    final url = widget.type == 'pdf' ? data.pdfUrl : data.videoUrl;
    if (url.isEmpty) return const Center(child: Text('Fayl kiritilmagan'));

    return Column(
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(data.artikul,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              IconButton(
                onPressed: _toggleFullScreen,
                icon: const Icon(Icons.fullscreen),
                tooltip: 'To\'liq ekran',
              ),
              Icon(
                widget.type == 'video'
                    ? Icons.video_library
                    : Icons.picture_as_pdf,
                color: widget.type == 'video'
                    ? AppColors.accent
                    : AppColors.danger,
              ),
            ],
          ),
        ),
        Expanded(child: _buildMediaContent(url, data)),
      ],
    );
  }

  Widget _buildFullScreenView() {
    final data = ref.read(moduleDataProvider);
    if (data == null) return const SizedBox();
    final url = widget.type == 'pdf' ? data.pdfUrl : data.videoUrl;

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          _buildMediaContent(url, data),
          Positioned(
            top: 40,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _toggleFullScreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent(String url, var data) {
    if (widget.type == 'video') {
      _initYoutube(url);
      return _isWeb
          ? Padding(
              padding: const EdgeInsets.all(0.0),
              child: buildWebIframe(_getIframeUrl(url, true), true,
                  key: ValueKey('vid_${data.artikul}')),
            )
          : _ytController != null
              ? YoutubePlayer(
                  controller: _ytController!,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: AppColors.accent,
                )
              : const Center(child: Text('Noto\'g\'ri video URL'));
    }

    // PDF View
    _initPdf(url);

    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _transformationController,
          maxScale: 5.0,
          minScale: 0.5,
          child: Center(
            child: _isWeb
                ? buildWebIframe(_getIframeUrl(url, false), false,
                    key: ValueKey('pdf_${data.artikul}'))
                : _isLoadingPdf
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.accent))
                    : _hasPdfError || _pdfController == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline,
                                    size: 48, color: AppColors.textGray),
                                const SizedBox(height: 16),
                                const Text(
                                    'Chizmani ilova ichida yuklashda xatolik yuz berdi.'),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
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
                            onPageChanged: (page) {
                              setState(() => _currentPage = page);
                            },
                          ),
          ),
        ),
        if (widget.type == 'pdf' && !_isLoadingPdf && !_hasPdfError && !_isWeb)
          _buildFloatingControlBar(),
      ],
    );
  }

  Widget _buildFloatingControlBar() {
    return Positioned(
      bottom: _isFullScreen ? 24 : 16,
      left: 16,
      right: 16,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_totalPages > 0) ...[
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      icon: const Icon(Icons.chevron_left,
                          color: Colors.white, size: 18),
                      onPressed: _currentPage > 1
                          ? () => _pdfController?.animateToPage(
                              _currentPage - 1,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeIn)
                          : null,
                    ),
                    Text(
                      '$_currentPage / $_totalPages',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      icon: const Icon(Icons.chevron_right,
                          color: Colors.white, size: 18),
                      onPressed: _currentPage < _totalPages
                          ? () => _pdfController?.animateToPage(
                              _currentPage + 1,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeIn)
                          : null,
                    ),
                    Container(
                      height: 16,
                      width: 1,
                      color: Colors.white24,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ],
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    icon:
                        const Icon(Icons.remove, color: Colors.white, size: 18),
                    onPressed: () => _zoom(0.8),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    icon: const Icon(Icons.refresh,
                        color: Colors.white, size: 16),
                    onPressed: _resetZoom,
                  ),
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    icon: const Icon(Icons.add, color: Colors.white, size: 18),
                    onPressed: () => _zoom(1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
