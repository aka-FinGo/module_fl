import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io';
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
  final bool _isWeb =
      const bool.fromEnvironment('dart.library.html', defaultValue: false);

  bool _isOnline = true;
  bool _isLoading = true;
  String? _errorMessage;

  // PDF uchun
  PdfController? _pdfController;
  int _pdfCurrentPage = 1;
  int _pdfTotalPages = 1;
  bool _isPdfLandscape = false;

  // Video uchun (WebView)
  WebViewController? _videoController;

  late final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkConnectivity());

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final isNowOnline = results.first != ConnectivityResult.none;
      setState(() => _isOnline = isNowOnline);
      if (widget.type == 'pdf' && isNowOnline && _pdfController == null && !_isWeb) {
        _initPdf();
      }
    });

    if (_isWeb && widget.type == 'pdf') setWebZoomable(true);
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (mounted) setState(() => _isOnline = result.first != ConnectivityResult.none);
    } catch (_) {}

    if (widget.type == 'pdf') {
      await _initPdf();
    } else {
      await _initVideo();
    }
  }

  // --- VIDEO ---
  Future<void> _initVideo() async {
    if (_isWeb) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final data = ref.read(moduleDataProvider);
    if (data == null || data.videoUrl.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'Video manzili kiritilmagan'; });
      return;
    }

    final embedUrl = _buildYoutubeEmbedUrl(data.videoUrl);
    if (embedUrl == null) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'Noto\'g\'ri YouTube URL'; });
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
        onWebResourceError: (error) {
          if (mounted) setState(() {
            _isLoading = false;
            _errorMessage = 'Video yuklanmadi. Internet aloqasini tekshiring.';
          });
        },
      ))
      ..loadRequest(Uri.parse(embedUrl));

    if (mounted) setState(() => _videoController = controller);
  }

  String? _buildYoutubeEmbedUrl(String url) {
    String? videoId;
    if (url.contains('youtu.be/')) {
      videoId = url.split('youtu.be/')[1].split('?')[0];
    } else if (url.contains('youtube.com/watch')) {
      videoId = Uri.parse(url).queryParameters['v'];
    } else if (url.contains('youtube.com/embed/')) {
      videoId = url.split('youtube.com/embed/')[1].split('?')[0];
    }
    if (videoId == null || videoId.isEmpty) return null;
    return 'https://www.youtube.com/embed/$videoId?autoplay=0&rel=0&modestbranding=1&controls=1';
  }

  // --- PDF ---
  String _buildPdfDownloadUrl(String originalUrl) {
    final match = RegExp(r'[-\w]{25,}').firstMatch(originalUrl);
    if (match != null) {
      return 'https://drive.google.com/uc?export=download&id=${match.group(0)}';
    }
    return originalUrl;
  }

  Future<File> _getCacheFile(String url) async {
    final dir = await getTemporaryDirectory();
    final match = RegExp(r'[-\w]{25,}').firstMatch(url);
    final fileName = match != null ? 'pdf_${match.group(0)}.pdf' : 'pdf_cache.pdf';
    return File('${dir.path}/$fileName');
  }

  Future<void> _initPdf() async {
    if (_isWeb) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final data = ref.read(moduleDataProvider);
    if (data == null || data.pdfUrl.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'PDF manzili kiritilmagan'; });
      return;
    }

    if (mounted) setState(() { _isLoading = true; _errorMessage = null; });

    final downloadUrl = _buildPdfDownloadUrl(data.pdfUrl);
    final cacheFile = await _getCacheFile(data.pdfUrl);

    try {
      // 1. Keshdan ochish
      if (await cacheFile.exists() && await cacheFile.length() > 1024) {
        try {
          final controller = PdfController(document: PdfDocument.openFile(cacheFile.path));
          if (mounted) {
            setState(() {
              _pdfController?.dispose();
              _pdfController = controller;
              _isLoading = false;
            });
          }
          if (_isOnline) _downloadPdfToCache(downloadUrl, cacheFile);
          return;
        } catch (_) {
          await cacheFile.delete();
        }
      }

      // 2. Yuklab olish
      if (_isOnline) {
        await _downloadPdfToCache(downloadUrl, cacheFile);
        if (await cacheFile.exists() && await cacheFile.length() > 1024) {
          final controller = PdfController(document: PdfDocument.openFile(cacheFile.path));
          if (mounted) {
            setState(() {
              _pdfController?.dispose();
              _pdfController = controller;
              _isLoading = false;
            });
          }
          return;
        }
      }

      // 3. Offline + keshda yo'q
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = _isOnline
              ? 'PDF yuklab bo\'lib bo\'lmadi. Qayta urinib ko\'ring.'
              : 'Offline rejim: PDF keshda yo\'q.\nInternetga ulanib bir marta oching.';
        });
      }
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'PDF ochishda xatolik.'; });
    }
  }

  Future<void> _downloadPdfToCache(String url, File cacheFile) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200 && response.bodyBytes.length > 1024) {
        await cacheFile.writeAsBytes(response.bodyBytes);
      }
    } catch (_) {}
  }

  void _toggleFullScreen() {
    final isFullScreen = ref.read(isFullScreenProvider);
    ref.read(isFullScreenProvider.notifier).state = !isFullScreen;
    if (!isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _togglePdfRotate() {
    setState(() => _isPdfLandscape = !_isPdfLandscape);
    if (_isPdfLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  String _getIframeUrl(String originalUrl) {
    final match = RegExp(r'[-\w]{25,}').firstMatch(originalUrl);
    if (match != null) {
      return 'https://docs.google.com/viewer?url=${Uri.encodeComponent('https://drive.google.com/uc?export=download&id=${match.group(0)}')}&embedded=true';
    }
    return originalUrl;
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _pdfController?.dispose();
    if (_isWeb && widget.type == 'pdf') setWebZoomable(false);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFullScreen = ref.watch(isFullScreenProvider);
    if (isFullScreen) return _buildFullScreenView();

    final data = ref.watch(moduleDataProvider);
    if (data == null) return const Center(child: Text('Ma\'lumot yo\'q'));

    final url = widget.type == 'pdf' ? data.pdfUrl : data.videoUrl;
    if (url.isEmpty) {
      return Center(
        child: Text(
          widget.type == 'pdf' ? 'Chizma kiritilmagan' : 'Video kiritilmagan',
          style: const TextStyle(color: AppColors.textGray),
        ),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(data.artikul,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              if (!_isOnline)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.wifi_off, color: Colors.orange, size: 20),
                ),
              // PDF uchun rotate tugmasi
              if (widget.type == 'pdf' && _pdfController != null) ...[
                IconButton(
                  onPressed: _togglePdfRotate,
                  icon: Icon(
                    _isPdfLandscape ? Icons.stay_primary_portrait : Icons.stay_primary_landscape,
                    color: AppColors.primary,
                  ),
                  tooltip: 'Burish',
                ),
              ],
              IconButton(
                onPressed: _toggleFullScreen,
                icon: const Icon(Icons.fullscreen),
                tooltip: 'To\'liq ekran',
              ),
              Icon(
                widget.type == 'video' ? Icons.video_library : Icons.picture_as_pdf,
                color: widget.type == 'video' ? AppColors.accent : AppColors.danger,
              ),
            ],
          ),
        ),
        // PDF sahifa ko'rsatgich
        if (widget.type == 'pdf' && _pdfController != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '$_pdfCurrentPage / $_pdfTotalPages',
              style: const TextStyle(color: AppColors.textGray, fontSize: 12),
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
      color: widget.type == 'pdf' ? Colors.white : Colors.black,
      child: Stack(
        children: [
          _buildMediaContent(url, data),
          if (widget.type == 'video')
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: PointerInterceptor(
                child: Container(
                  height: 50,
                  color: Colors.black.withOpacity(0.85),
                  child: const Center(
                    child: Text('Xavfsiz Ko\'rish Rejimi',
                        style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
    // Yuklanish
    if (_isLoading && widget.type == 'pdf') {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 12),
            Text('PDF yuklanmoqda...', style: TextStyle(color: AppColors.textGray)),
          ],
        ),
      );
    }

    // Xatolik
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isOnline ? Icons.error_outline : Icons.wifi_off,
                color: _isOnline ? AppColors.danger : Colors.orange,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textGray, height: 1.5)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() { _isLoading = true; _errorMessage = null; });
                  if (widget.type == 'pdf') _initPdf();
                  else _initVideo();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Qayta urinish'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              ),
            ],
          ),
        ),
      );
    }

    // VIDEO — WebView (ham mobile, ham web)
    if (widget.type == 'video') {
      if (_isWeb) {
        final embedUrl = _buildYoutubeEmbedUrl(url) ?? url;
        return buildWebIframe(embedUrl, true, key: ValueKey('vid_${data.artikul}'));
      }
      // Mobile WebView
      if (_videoController != null) {
        return Stack(
          children: [
            WebViewWidget(controller: _videoController!),
            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    // PDF — Mobile keshdan
    if (!_isWeb && _pdfController != null) {
      return PdfView(
        controller: _pdfController!,
        scrollDirection: Axis.vertical,
        onDocumentLoaded: (document) {
          if (mounted) setState(() => _pdfTotalPages = document.pagesCount);
        },
        onPageChanged: (page) {
          if (mounted) setState(() => _pdfCurrentPage = page);
        },
      );
    }

    // PDF — Web fallback
    return buildWebIframe(_getIframeUrl(url), false,
        key: ValueKey('pdf_${data.artikul}'));
  }
}
