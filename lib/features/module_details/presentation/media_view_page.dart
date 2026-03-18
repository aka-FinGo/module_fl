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

  // PDF — ikki rejim (mobile)
  PdfController?     _pdfController;
  WebViewController? _pdfWebViewController;
  bool _isPdfNative    = false;
  int  _pdfCurrentPage = 1;
  int  _pdfTotalPages  = 1;
  bool _isPdfLandscape = false;

  // Video — WebView (mobile)
  WebViewController? _videoWebViewController;

  // Web platform uchun iframe URL
  String? _webUrl;
  bool    _webIsVideo = false; // video uchun <video> tag ishlatish

  late final StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  // ─── HELPERS ─────────────────────────────────────────────
  bool _isDriveUrl(String url)   => url.contains('drive.google.com');
  bool _isYoutubeUrl(String url) => url.contains('youtu.be') || url.contains('youtube.com');
  bool _isTelegramUrl(String url)=> url.contains('api.telegram.org');

  String _extractDriveId(String url) =>
      RegExp(r'[-\w]{25,}').firstMatch(url)?.group(0) ?? '';

  String _buildDrivePreviewUrl(String url) {
    final id = _extractDriveId(url);
    return id.isNotEmpty ? 'https://drive.google.com/file/d/$id/preview' : url;
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

  // Telegram PDF → Google Docs Viewer orqali ko'rsatish
  String _buildDocsViewerUrl(String fileUrl) {
    final encoded = Uri.encodeComponent(fileUrl);
    return 'https://docs.google.com/viewer?url=$encoded&embedded=true';
  }

  String _buildVideoEmbedUrl(String url) {
    if (_isYoutubeUrl(url)) return _buildYoutubeEmbedUrl(url);
    if (_isDriveUrl(url))   return _buildDrivePreviewUrl(url);
    return url;
  }

  // ─── INIT ────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkConnectivity());
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final online = results.first != ConnectivityResult.none;
      setState(() => _isOnline = online);
      if (widget.type == 'pdf' && online && !_isPdfNative && !_isWeb) {
        _tryDownloadPdfInBackground();
      }
    });
    if (_isWeb && widget.type == 'pdf') setWebZoomable(true);
  }

  Future<void> _checkConnectivity() async {
    try {
      final r = await Connectivity().checkConnectivity();
      if (mounted) setState(() => _isOnline = r.first != ConnectivityResult.none);
    } catch (_) {}
    if (widget.type == 'pdf') {
      await _initPdf();
    } else {
      await _initVideo();
    }
  }

  // ─── VIDEO ───────────────────────────────────────────────
  Future<void> _initVideo() async {
    final data = ref.read(moduleDataProvider);
    if (data == null) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'Ma\'lumot yo\'q'; });
      return;
    }

    // ── WEB PLATFORM ────────────────────────────────────────
    if (_isWeb) {
      String? url;
      bool isDirectVideo = false;

      // 1. Telegram ID — prioritet (Drive/YouTube dan oldin)
      if (data.tgVideoId.isNotEmpty && _isOnline) {
        final tgUrl = await _getTelegramUrl(data.tgVideoId);
        if (tgUrl != null && tgUrl.isNotEmpty) {
          url = tgUrl;
          isDirectVideo = true; // <video> tag ishlatamiz
        }
      }

      // 2. YouTube embed
      if (url == null && data.videoUrl.isNotEmpty && _isYoutubeUrl(data.videoUrl)) {
        url = _buildYoutubeEmbedUrl(data.videoUrl);
      }

      // 3. Drive /preview iframe
      if (url == null && data.videoUrl.isNotEmpty && _isDriveUrl(data.videoUrl)) {
        url = _buildDrivePreviewUrl(data.videoUrl);
      }

      // 4. Boshqa URL
      if (url == null && data.videoUrl.isNotEmpty) {
        url = data.videoUrl;
        isDirectVideo = true;
      }

      if (mounted) setState(() {
        _webUrl = url;
        _webIsVideo = isDirectVideo;
        _isLoading = false;
        if (url == null) _errorMessage = 'Video manbai topilmadi';
      });
      return;
    }

    // ── MOBILE PLATFORM ─────────────────────────────────────
    if (data.tgVideoId.isNotEmpty && _isOnline) {
      final url = await _getTelegramUrl(data.tgVideoId);
      if (url != null) { _loadVideoWebView(url); return; }
    }
    if (data.videoUrl.isNotEmpty) {
      _loadVideoWebView(_buildVideoEmbedUrl(data.videoUrl));
      return;
    }
    if (mounted) setState(() { _isLoading = false; _errorMessage = 'Video kiritilmagan'; });
  }

  void _loadVideoWebView(String url) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted) setState(() => _isLoading = false); },
        onWebResourceError: (err) {
          if (err.isForMainFrame != false && mounted) {
            setState(() { _isLoading = false; _errorMessage = 'Video yuklanmadi.'; });
          }
        },
      ))
      ..loadRequest(Uri.parse(url));
    if (mounted) setState(() => _videoWebViewController = controller);
  }

  // ─── PDF ─────────────────────────────────────────────────
  Future<void> _initPdf() async {
    final data = ref.read(moduleDataProvider);
    if (data == null || !data.hasPdf) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'PDF kiritilmagan'; });
      return;
    }

    // ── WEB PLATFORM ────────────────────────────────────────
    if (_isWeb) {
      String? url;

      // 1. Telegram ID — prioritet (har doim birinchi)
      if (data.tgPdfId.isNotEmpty && _isOnline) {
        final tgUrl = await _getTelegramUrl(data.tgPdfId);
        if (tgUrl != null && tgUrl.isNotEmpty) {
          // Telegram URL → Google Docs Viewer orqali ko'rsatamiz
          url = _buildDocsViewerUrl(tgUrl);
        }
      }

      // 2. Drive URL (faqat Telegram muvaffaqiyatsiz bo'lganda)
      if (url == null && data.pdfUrl.isNotEmpty && _isDriveUrl(data.pdfUrl)) {
        url = _buildDrivePreviewUrl(data.pdfUrl);
      }

      // 3. Boshqa to'g'ridan URL
      if (url == null && data.pdfUrl.isNotEmpty) {
        url = _buildDocsViewerUrl(data.pdfUrl);
      }

      if (mounted) setState(() {
        _webUrl = url;
        _isLoading = false;
        if (url == null) {
          _errorMessage = _isOnline
              ? 'PDF manbai topilmadi'
              : 'Offline: Internet kerak';
        }
      });
      return;
    }

    // ── MOBILE PLATFORM ─────────────────────────────────────
    // 1. Keshni tekshirish
    final cacheKey  = data.tgPdfId.isNotEmpty ? data.tgPdfId : data.pdfUrl;
    final cacheFile = await _getCacheFile(cacheKey);

    if (await cacheFile.exists() && await cacheFile.length() > 1024) {
      try {
        final ctrl = PdfController(document: PdfDocument.openFile(cacheFile.path));
        if (mounted) setState(() {
          _pdfController?.dispose();
          _pdfController = ctrl;
          _isPdfNative = true;
          _isLoading = false;
        });
        if (_isOnline) _tryDownloadPdfInBackground();
        return;
      } catch (_) { await cacheFile.delete(); }
    }

    // 2. Drive WebView /preview (darhol ko'rsatish)
    if (data.pdfUrl.isNotEmpty && _isDriveUrl(data.pdfUrl)) {
      _initPdfWebView(data.pdfUrl);
    } else if (data.tgPdfId.isEmpty && !_isOnline) {
      if (mounted) setState(() {
        _isLoading = false;
        _errorMessage = 'Offline: PDF keshda yo\'q.\nInternetga ulanib bir marta oching.';
      });
      return;
    } else {
      if (mounted) setState(() => _isLoading = true);
    }
    if (_isOnline) _tryDownloadPdfInBackground();
  }

  void _initPdfWebView(String url) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF525659))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted && !_isPdfNative) setState(() => _isLoading = false);
        },
        onWebResourceError: (err) {
          if (err.isForMainFrame != false && mounted && !_isPdfNative) {
            setState(() { _isLoading = false; _errorMessage = 'PDF yuklanmadi.'; });
          }
        },
      ))
      ..loadRequest(Uri.parse(_buildDrivePreviewUrl(url)));
    if (mounted && !_isPdfNative) setState(() => _pdfWebViewController = controller);
  }

  Future<void> _tryDownloadPdfInBackground() async {
    final data = ref.read(moduleDataProvider);
    if (data == null) return;

    String? downloadUrl;
    if (data.tgPdfId.isNotEmpty) {
      downloadUrl = await _getTelegramUrl(data.tgPdfId);
    }
    if (downloadUrl == null && data.pdfUrl.isNotEmpty) {
      downloadUrl = _buildDriveDownloadUrl(data.pdfUrl);
    }
    if (downloadUrl == null) return;

    final cacheKey  = data.tgPdfId.isNotEmpty ? data.tgPdfId : data.pdfUrl;
    final cacheFile = await _getCacheFile(cacheKey);
    final ok        = await _downloadPdf(downloadUrl, cacheFile);
    if (!ok) return;

    try {
      final ctrl = PdfController(document: PdfDocument.openFile(cacheFile.path));
      if (mounted) {
        setState(() {
          _pdfController?.dispose();
          _pdfController = ctrl;
          _isPdfNative = true;
          _pdfWebViewController = null;
        });
      }
    } catch (_) {}
  }

  // ─── Telegram URL proxy ───────────────────────────────────
  Future<String?> _getTelegramUrl(String fileId) async {
    try {
      final repo = ref.read(apiRepositoryProvider);
      return await repo.getTelegramFileUrl(fileId);
    } catch (_) {
      return null;
    }
  }

  // ─── PDF download (mobile) ────────────────────────────────
  Future<File> _getCacheFile(String key) async {
    final dir      = await getTemporaryDirectory();
    final safeName = key.replaceAll(RegExp(r'[^\w]'), '_');
    return File('${dir.path}/pdf_$safeName.pdf');
  }

  Future<bool> _downloadPdf(String url, File file) async {
    try {
      var response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 90));
      final ct = response.headers['content-type'] ?? '';
      if (ct.contains('text/html')) {
        final body         = response.body;
        final uuidMatch    = RegExp(r'uuid=([^&>\s]+)').firstMatch(body);
        final confirmMatch = RegExp(r'confirm=([^&>\s]+)').firstMatch(body);
        final actionMatch  = RegExp(r'action="([^"]+)"').firstMatch(body);
        String newUrl = url;
        if (uuidMatch != null) {
          newUrl = '$url&uuid=${uuidMatch.group(1)}';
        } else if (confirmMatch != null && confirmMatch.group(1) != 't') {
          newUrl = '$url&confirm=${confirmMatch.group(1)}';
        } else if (actionMatch != null) {
          newUrl = actionMatch.group(1)!.replaceAll('&amp;', '&');
        }
        if (newUrl != url) {
          response = await http.get(Uri.parse(newUrl))
              .timeout(const Duration(seconds: 90));
        }
      }
      if (response.statusCode == 200 && response.bodyBytes.length > 1024) {
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

  // ─── FULLSCREEN & ROTATE ──────────────────────────────────
  void _toggleFullScreen() {
    final fs = ref.read(isFullScreenProvider);
    ref.read(isFullScreenProvider.notifier).state = !fs;
    if (!fs) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
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
    _connectivitySub.cancel();
    _pdfController?.dispose();
    if (_isWeb && widget.type == 'pdf') setWebZoomable(false);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─── BUILD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isFullScreen = ref.watch(isFullScreenProvider);
    if (isFullScreen) return _buildFullScreenView();

    final data = ref.watch(moduleDataProvider);
    if (data == null) return const Center(child: Text('Ma\'lumot yo\'q'));

    final hasContent = widget.type == 'pdf' ? data.hasPdf : data.hasVideo;
    if (!hasContent) {
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
        _buildTopBar(data),
        if (widget.type == 'pdf' && _isPdfNative && _pdfController != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('$_pdfCurrentPage / $_pdfTotalPages',
                style: const TextStyle(color: AppColors.textGray, fontSize: 12)),
          ),
        if (_isLoading && _isWeb)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 10, height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textGray)),
                SizedBox(width: 6),
                Text('Telegram\'dan URL yuklanmoqda...',
                    style: TextStyle(color: AppColors.textGray, fontSize: 11)),
              ],
            ),
          ),
        if (widget.type == 'pdf' && !_isWeb && !_isPdfNative && _isOnline &&
            (_pdfWebViewController != null || _isLoading))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textGray),
                ),
                const SizedBox(width: 6),
                Text(
                  ref.read(moduleDataProvider)?.tgPdfId.isNotEmpty == true
                      ? 'Telegram\'dan yuklanmoqda...'
                      : 'Native rejim yuklanmoqda...',
                  style: const TextStyle(color: AppColors.textGray, fontSize: 11),
                ),
              ],
            ),
          ),
        Expanded(child: _buildContent(data)),
      ],
    );
  }

  Widget _buildTopBar(dynamic data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(data.artikul,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          if (!_isOnline)
            const Padding(padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.wifi_off, color: Colors.orange, size: 18)),
          if (widget.type == 'pdf' && (data.tgPdfId?.isNotEmpty == true))
            const Tooltip(message: 'Telegram\'dan yuklanadi',
              child: Padding(padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('✈️', style: TextStyle(fontSize: 16)))),
          if (widget.type == 'video' && (data.tgVideoId?.isNotEmpty == true))
            const Tooltip(message: 'Telegram\'dan yuklanadi',
              child: Padding(padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('✈️', style: TextStyle(fontSize: 16)))),
          if (widget.type == 'pdf' && _isPdfNative && _pdfController != null)
            IconButton(
              onPressed: _togglePdfRotate,
              icon: Icon(
                _isPdfLandscape ? Icons.stay_primary_portrait : Icons.stay_primary_landscape,
                color: AppColors.primary,
              ),
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
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          _buildContent(data),
          if (widget.type == 'video')
            Positioned(top: 0, right: 0,
              child: PointerInterceptor(
                child: Container(width: 70, height: 70, color: Colors.transparent))),
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

  Widget _buildContent(dynamic data) {
    // ── Loading ───────────────────────────────────────────
    if (_isLoading &&
        _videoWebViewController == null &&
        _pdfWebViewController == null &&
        _pdfController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.accent),
            const SizedBox(height: 12),
            Text(
              (data.tgPdfId?.isNotEmpty == true || data.tgVideoId?.isNotEmpty == true)
                  ? 'Telegram\'dan URL olinmoqda...'
                  : 'Yuklanmoqda...',
              style: const TextStyle(color: AppColors.textGray),
            ),
          ],
        ),
      );
    }

    // ── Error ─────────────────────────────────────────────
    if (_errorMessage != null &&
        _pdfWebViewController == null &&
        _pdfController == null &&
        _webUrl == null) {
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
                    _isLoading = true; _errorMessage = null;
                    _isPdfNative = false; _pdfWebViewController = null;
                    _webUrl = null;
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

    // ── VIDEO ─────────────────────────────────────────────
    if (widget.type == 'video') {
      if (_isWeb) {
        final url = _webUrl ?? '';
        if (url.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        // Telegram to'g'ridan URL → <video> tag
        // YouTube/Drive → iframe
        return buildWebIframe(url, true,
            isDirectVideo: _webIsVideo,
            key: ValueKey('vid_${data.artikul}_$url'));
      }
      if (_videoWebViewController != null) {
        return Stack(
          children: [
            WebViewWidget(controller: _videoWebViewController!),
            Positioned(top: 0, right: 0,
              child: PointerInterceptor(
                child: Container(width: 70, height: 70, color: Colors.transparent))),
            Positioned(bottom: 0, left: 0, right: 0,
              child: PointerInterceptor(
                child: Container(height: 44, color: Colors.transparent))),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    // ── PDF ───────────────────────────────────────────────
    if (_isWeb) {
      final url = _webUrl ?? '';
      if (url.isEmpty) {
        return const Center(child: CircularProgressIndicator(color: AppColors.accent));
      }
      return buildWebIframe(url, false,
          key: ValueKey('pdf_${data.artikul}_$url'));
    }

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

    if (_pdfWebViewController != null) {
      return Stack(
        children: [
          WebViewWidget(controller: _pdfWebViewController!),
          Positioned(top: 0, right: 0,
            child: PointerInterceptor(
              child: Container(width: 80, height: 80, color: Colors.transparent))),
        ],
      );
    }

    return const Center(child: CircularProgressIndicator(color: AppColors.accent));
  }
}
