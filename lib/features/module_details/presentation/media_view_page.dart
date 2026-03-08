import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pdfx/pdfx.dart';
import 'dart:io';
import 'dart:async';
import '../../../data/repositories/api_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/offline_cache_manager.dart';
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
  final bool _isWeb =
      const bool.fromEnvironment('dart.library.html', defaultValue: false);

  bool _isOnline = true;
  File? _cachedPdf;
  PdfController? _pdfController;
  late final StreamSubscription<List<ConnectivityResult>>
      _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        final result = results.first;
        setState(() {
          _isOnline = result != ConnectivityResult.none;
        });
        if (widget.type == 'pdf' && _isOnline && _pdfController == null) {
          _initOfflinePdf();
        }
      }
    });

    if (_isWeb && widget.type == 'pdf') {
      setWebZoomable(true);
    }
  }

  Future<void> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOnline = connectivityResult.first != ConnectivityResult.none;
      });
    }

    if (widget.type == 'pdf') {
      _initOfflinePdf();
    } else if (widget.type == 'video') {
      _initYoutube();
    }
  }

  Future<void> _initOfflinePdf() async {
    final data = ref.read(moduleDataProvider); // Fixed: StateProvider access
    if (data == null || data.pdfUrl.isEmpty) return;

    // Keshdan tekshirish
    final cached = await OfflineCacheManager.getCachedPdf(data.pdfUrl);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _cachedPdf = cached;
          _pdfController =
              PdfController(document: PdfDocument.openFile(cached.path));
        });
      }
    }

    // Agar online bo'lsak, fon rejimida keshga yuklab qo'yamiz (agar hali yo'q bo'lsa)
    if (_isOnline) {
      OfflineCacheManager.downloadToCache(data.pdfUrl);
    }
  }

  void _initYoutube() {
    if (_ytController != null || _isWeb) return;
    final data = ref.read(moduleDataProvider); // Fixed: StateProvider access
    if (data == null || data.videoUrl.isEmpty) return;

    final videoId = YoutubePlayer.convertUrlToId(data.videoUrl);
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

  void _toggleFullScreen() {
    final isFullScreen = ref.read(isFullScreenProvider);
    ref.read(isFullScreenProvider.notifier).state = !isFullScreen;

    if (!isFullScreen) {
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
  }

  String _getIframeUrl(String originalUrl, bool isVideo) {
    if (isVideo) {
      final vidId = YoutubePlayer.convertUrlToId(originalUrl) ?? "";
      return 'https://www.youtube.com/embed/$vidId?modestbranding=1&rel=0&controls=1&fs=0&iv_load_policy=3';
    }

    final match = RegExp(r'[-\w]{25,}').firstMatch(originalUrl);
    if (match != null) {
      final fileId = match.group(0);
      return 'https://docs.google.com/viewer?url=${Uri.encodeComponent('https://drive.google.com/uc?export=download&id=$fileId')}&embedded=true';
    }
    return originalUrl;
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _ytController?.dispose();
    _pdfController?.dispose();
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
    final isFullScreen = ref.watch(isFullScreenProvider);
    if (isFullScreen) {
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
    final data = ref.read(moduleDataProvider); // Fixed: StateProvider access
    if (data == null) return const SizedBox();
    final url = widget.type == 'pdf' ? data.pdfUrl : data.videoUrl;

    return Container(
      color: widget.type == 'pdf' ? Colors.white : Colors.black,
      child: Stack(
        children: [
          _buildMediaContent(url, data),
          if (widget.type == 'video')
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: OrientationBuilder(
                builder: (context, orientation) {
                  final height =
                      orientation == Orientation.portrait ? 80.0 : 60.0;
                  return PointerInterceptor(
                    child: Container(
                      height: height,
                      color: Colors.black.withOpacity(0.9),
                      child: const Center(
                        child: Text(
                          'Xavfsiz Ko\'rish Rejimi',
                          style: TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: PointerInterceptor(
                child: IconButton(
                  onPressed: _toggleFullScreen,
                  icon: const CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent(String url, dynamic data) {
    if (widget.type == 'video') {
      return _isWeb
          ? buildWebIframe(_getIframeUrl(url, true), true,
              key: ValueKey('vid_${data.artikul}'))
          : _ytController != null
              ? YoutubePlayer(
                  controller: _ytController!,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: AppColors.accent,
                )
              : const Center(child: Text('Video yuklanmoqda...'));
    }

    if (!_isWeb) {
      if (!_isOnline || _cachedPdf != null) {
        if (_pdfController != null) {
          return PdfView(
            controller: _pdfController!,
            scrollDirection: Axis.vertical,
          );
        } else if (!_isOnline) {
          return const Center(
            child: Text(
              'Offline rejim: Fayl keshda mavjud emas.\nInternetga ulanib qayta urinib ko\'ring.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          );
        }
      }
    }

    return buildWebIframe(_getIframeUrl(url, false), false,
        key: ValueKey('pdf_${data.artikul}'));
  }
}
