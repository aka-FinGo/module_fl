import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
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

  // PDF — ikki rejim
  PdfController? _pdfController;         // native pdfx (muvaffaqiyatli yuklab olgandan keyin)
  WebViewController? _pdfWebViewController; // WebView /preview (darhol)
  bool _isPdfNative = false;             // true bo'lsa pdfx ko'rsatiladi
  int _pdfCurrentPage = 1;
  int _pdfTotalPages = 1;
  bool _isPdfLandscape = false;

  // Video — WebView (Drive + YouTube)
  WebViewController? _videoWebViewController;

  late final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  // ─── HELPERS ──────────────────────────────────────────────────────
  bool _isDriveUrl(String url) => url.contains('drive.google.com');
  bool _isYoutubeUrl(String url) =>
      url.contains('youtu.be') || url.contains('youtube.com');

  String _extractDriveId(String url) {
    return RegExp(r'[-\w]{25,}').firstMatch(url)?.group(0) ?? '';
  }

  String _buildDrivePreviewUrl(String url) {
    final id = _extractDriveId(url);
    return id.isNotEmpty
        ? 'https://drive.google.com/file/d/$id/preview'
        : url;
  }

  String _buildDriveDownloadUrl(String url) {
    final id = _extractDriveId(url);
    return id.isNotEmpty
        ? 'https://drive.google.com/uc?export=download&confirm=t&id=$id'
        : url;
  }

  String _buildYoutubeEmbedUrl(String url) {
    String? videoId;
    if (url.contains('youtu.be/')) {
      videoId = url.split('youtu.be/')[1].split('?')[0];
    } else if (url.contains('youtube.com/watch')) {
      videoId = Uri.parse(url).queryParameters['v'];
    } else if (url.contains('youtube.com/embed/')) {
      videoId = url.split('youtube.com/embed/')[1].split('?')[0];
    }
    if (videoId != null && videoId.isNotEmpty) {
      return 'https://www.youtube.com/embed/$videoId?autoplay=0&rel=0&modestbranding=1&controls=1';
    }
    return url;
  }

  String _buildVideoEmbedUrl(String url) {
    if (_isYoutubeUrl(url)) return _buildYoutubeEmbedUrl(url);
    if (_isDriveUrl(url)) return _buildDrivePreviewUrl(url);
    return url;
  }

  // ─── INIT ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkConnectivity());
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final isNowOnline = results.first != ConnectivityResult.none;
      setState(() => _isOnline = isNowOnline);
      if (widget.type == 'pdf' && isNowOnline && !_isPdfNative && !_isWeb) {
        _tryDownloadPdfInBackground();
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

  // ─── VIDEO ────────────────────────────────────────────────────────
  Future<void> _initVideo() async {
    if (_isWeb) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final data = ref.read(moduleDataProvider);
    if (data == null || data.videoUrl.isEmpty) {
      if (mounted) setState(() {
        _isLoading = false;
        _errorMessage = 'Video manzili kiritilmagan';
      });
      return;
    }
    final url = data.videoUrl;
    String embedUrl;
    if (_isYoutubeUrl(url)) {
      embedUrl = _buildYoutubeEmbedUrl(url);
    } else if (_isDriveUrl(url)) {
      embedUrl = _buildDrivePreviewUrl(url);
    } else {
      embedUrl = url;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
        onWebResourceError: (_) {
          if (mounted) setState(() {
            _isLoading = false;
            _errorMessage = 'Video yuklanmadi. Internet aloqasini tekshiring.';
          });
        },
      ))
      ..loadRequest(Uri.parse(embedUrl));

    if (mounted) setState(() => _videoWebViewController = controller);
  }

  // ─── PDF ──────────────────────────────────────────────────────────
  Future<void> _initPdf() async {
    if (_isWeb) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final data = ref.read(moduleDataProvider);
    if (data == null || data.pdfUrl.isEmpty) {
      if (mounted) setState(() {
        _isLoading = false;
        _errorMessage = 'PDF manzili kiritilmagan';
      });
      return;
    }

    final url = data.pdfUrl;

    // 1. Avval keshni tekshir — mavjud bo'lsa darhol pdfx bilan ko'rsat
    if (_isOnline || true) {
      final cacheFile = await _getCacheFile(url);
      if (await cacheFile.exists() && await cacheFile.length() > 1024) {
        try {
          final controller = PdfController(document: PdfDocument.openFile(cacheFile.path));
          if (mounted) {
            setState(() {
              _pdfController?.dispose();
              _pdfController = controller;
              _isPdfNative = true;
              _isLoading = false;
            });
          }
          // Fonda yangilashtir
          if (_isOnline) _tryDownloadPdfInBackground();
          return;
        } catch (_) {
          await cacheFile.delete();
        }
      }
    }

    // 2. Kesh yo'q — darhol WebView /preview ko'rsat
    _initPdfWebView(url);

    // 3. Parallel ravishda yuklab olishga urinish
    if (_isOnline) _tryDownloadPdfInBackground();
  }

  void _initPdfWebView(String url) {
    final previewUrl = _buildDrivePreviewUrl(url);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF525659))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted && !_isPdfNative) setState(() => _isLoading = false);
        },
        onWebResourceError: (_) {
          if (mounted && !_isPdfNative) setState(() {
            _isLoading = false;
            _errorMessage = 'PDF yuklanmadi. Internet aloqasini tekshiring.';
          });
        },
      ))
      ..loadRequest(Uri.parse(previewUrl));

    if (mounted && !_isPdfNative) {
      setState(() => _pdfWebViewController = controller);
    }
  }

  /// Fon rejimda PDF yuklab olish — muvaffaqiyatli bo'lsa pdfx ga o'tish
  Future<void> _tryDownloadPdfInBackground() async {
    final data = ref.read(moduleDataProvider);
    if (data == null || data.pdfUrl.isEmpty) return;

    final url = data.pdfUrl;
    final cacheFile = await _getCacheFile(url);
    final downloadUrl = _buildDriveDownloadUrl(url);

    final ok = await _downloadPdf(downloadUrl, cacheFile);
    if (!ok) return;

    // Yuklab olindi — pdfx ga o'tish
    try {
      final controller = PdfController(document: PdfDocument.openFile(cacheFile.path));
      if (mounted) {
        setState(() {
          _pdfController?.dispose();
          _pdfController = controller;
          _isPdfNative = true;
          // WebView ni endi ishlatmaymiz
          _pdfWebViewController = null;
        });
      }
    } catch (_) {}
  }

  Future<File> _getCacheFile(String url) async {
    final dir = await getTemporaryDirectory();
    final id = _extractDriveId(url);
    final fileName = id.isNotEmpty ? 'pdf_$id.pdf' : 'pdf_cache.pdf';
    return File('${dir.path}/$fileName');
  }

  /// Drive virus-scan confirmation bypass bilan yuklab olish
  Future<bool> _downloadPdf(String url, File file) async {
    try {
      var response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));

      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('text/html')) {
        final body = response.body;
        final uuidMatch = RegExp(r'uuid=([^&>\s]+)').firstMatch(body);
        final confirmMatch = RegExp(r'confirm=([^&>\s]+)').firstMatch(body);
        final actionMatch = RegExp(r'action="([^"]+)"').firstMatch(body);

        String newUrl = url;
        if (uuidMatch != null) {
          newUrl = '$url&uuid=${uuidMatch.group(1)}';
        } else if (confirmMatch != null && confirmMatch.group(1) != 't') {
          newUrl = '$url&confirm=${confirmMatch.group(1)}';
        } else if (actionMatch != null) {
          newUrl = actionMatch.group(1)!.replaceAll('&amp;', '&');
        }

        if (newUrl != url) {
          response = await http.get(Uri.parse(newUrl)).timeout(const Duration(seconds: 60));
        }
      }

      if (response.statusCode == 200 && response.bodyBytes.length > 1024) {
        // PDF signature tekshiruvi
        final bytes = response.bodyBytes;
        if (bytes.length >= 4 &&
            bytes[0] == 0x25 && bytes[1] == 0x50 &&
            bytes[2] == 0x44 && bytes[3] == 0x46) {
          await file.writeAsBytes(bytes);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  // ─── FULLSCREEN & ROTATE ──────────────────────────────────────────
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
    SystemChrome.setPreferredOrientations(_isPdfLandscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
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

  // ─── BUILD ────────────────────────────────────────────────────────
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
            style: const TextStyle(color: AppColors.textGray)),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 10),
        _buildTopBar(data, url),
        // Sahifa raqami — faqat native pdfx rejimida
        if (widget.type == 'pdf' && _isPdfNative && _pdfController != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('$_pdfCurrentPage / $_pdfTotalPages',
                style: const TextStyle(color: AppColors.textGray, fontSize: 12)),
          ),
        // WebView rejimida "fonda yuklanmoqda" ko'rsatkich
        if (widget.type == 'pdf' && !_isPdfNative && _pdfWebViewController != null && _isOnline)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textGray),
                ),
                const SizedBox(width: 6),
                const Text('Native rejim yuklanmoqda...',
                    style: TextStyle(color: AppColors.textGray, fontSize: 11)),
              ],
            ),
          ),
        Expanded(child: _buildContent(url, data)),
      ],
    );
  }

  Widget _buildTopBar(dynamic data, String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(data.artikul,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          if (!_isOnline)
            const Padding(padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.wifi_off, color: Colors.orange, size: 18)),
          // Rotate — faqat native pdfx rejimida
          if (widget.type == 'pdf' && _isPdfNative && _pdfController != null)
            IconButton(
              onPressed: _togglePdfRotate,
              icon: Icon(
                _isPdfLandscape
                    ? Icons.stay_primary_portrait
                    : Icons.stay_primary_landscape,
                color: AppColors.primary),
              tooltip: 'Burish',
            ),
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
          _buildContent(url, data),
          if (widget.type == 'video' && _isYoutubeUrl(data.videoUrl))
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
          if (widget.type == 'video')
            Positioned(
              top: 0, right: 0,
              child: PointerInterceptor(
                child: Container(width: 70, height: 70, color: Colors.transparent),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
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

  Widget _buildContent(String url, dynamic data) {
    if (_isLoading &&
        _videoWebViewController == null &&
        _pdfWebViewController == null &&
        _pdfController == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 12),
            Text('Yuklanmoqda...', style: TextStyle(color: AppColors.textGray)),
          ],
        ),
      );
    }

    if (_errorMessage != null &&
        _pdfWebViewController == null &&
        _pdfController == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_isOnline ? Icons.error_outline : Icons.wifi_off,
                  color: _isOnline ? AppColors.danger : Colors.orange, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textGray, height: 1.5)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                    _isPdfNative = false;
                    _pdfWebViewController = null;
                  });
                  if (widget.type == 'pdf') _initPdf(); else _initVideo();
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

    // ── VIDEO ──────────────────────────────────────────────────────
    if (widget.type == 'video') {
      if (_isWeb) {
        return buildWebIframe(_buildVideoEmbedUrl(url), true,
            key: ValueKey('vid_${data.artikul}'));
      }
      if (_videoWebViewController != null) {
        final isDrive = _isDriveUrl(url);
        return Stack(
          children: [
            WebViewWidget(controller: _videoWebViewController!),
            Positioned(
              top: 0, right: 0,
              child: PointerInterceptor(
                child: Container(width: 70, height: 70, color: Colors.transparent),
              ),
            ),
            if (!isDrive)
              Positioned(
                bottom: 0, left: 0,
                child: PointerInterceptor(
                  child: Container(width: 160, height: 50, color: Colors.transparent),
                ),
              ),
            if (isDrive)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: PointerInterceptor(
                  child: Container(height: 44, color: Colors.transparent),
                ),
              ),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    // ── PDF ────────────────────────────────────────────────────────
    // Web
    if (_isWeb) {
      return buildWebIframe(url, false, key: ValueKey('pdf_${data.artikul}'));
    }

    // Mobile: native pdfx (yuklab olingandan keyin)
    if (_isPdfNative && _pdfController != null) {
      return PdfView(
        controller: _pdfController!,
        scrollDirection: Axis.vertical,
        onDocumentLoaded: (doc) {
          if (mounted) setState(() => _pdfTotalPages = doc.pagesCount);
        },
        onPageChanged: (page) {
          if (mounted) setState(() => _pdfCurrentPage = page);
        },
      );
    }

    // Mobile: WebView /preview (darhol ko'rinadi, yuklab olish kutilmoqda)
    if (_pdfWebViewController != null) {
      return WebViewWidget(controller: _pdfWebViewController!);
    }

    return const Center(child: CircularProgressIndicator(color: AppColors.accent));
  }
}
