import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pdfx/pdfx.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../data/repositories/api_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../shell/presentation/shell_page.dart';
import 'web_iframe_stub.dart' if (dart.library.html) 'web_iframe.dart';
import 'media_pdf_helper.dart';
import 'custom_youtube_html.dart';

class MediaViewPage extends ConsumerStatefulWidget {
  final String type;
  const MediaViewPage({super.key, required this.type});
  @override
  ConsumerState<MediaViewPage> createState() => _MediaViewPageState();
}

class _MediaViewPageState extends ConsumerState<MediaViewPage> {
  final bool _isWeb = const bool.fromEnvironment('dart.library.html', defaultValue: false);

  bool _isOnline = true;
  bool _isLoading = true;
  String? _error;

  // PDF
  PdfController? _pdfCtrl;
  WebViewController? _pdfWeb;
  bool _isPdfNative = false;
  int _pdfPage = 1, _pdfTotal = 1;
  bool _isPdfLandscape = false;

  // Video
  WebViewController? _videoWeb;

  late final StreamSubscription<List<ConnectivityResult>> _conSub;

  bool _isDrive(String u) => u.contains('drive.google.com');
  bool _isYt(String u) => u.contains('youtu.be') || u.contains('youtube.com');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    _conSub = Connectivity().onConnectivityChanged.listen((r) {
      if (!mounted) return;
      final on = r.first != ConnectivityResult.none;
      setState(() => _isOnline = on);
      if (widget.type == 'pdf' && on && !_isPdfNative && !_isWeb) _downloadPdf();
    });
    if (_isWeb && widget.type == 'pdf') setWebZoomable(true);
  }

  Future<void> _init() async {
    try {
      final r = await Connectivity().checkConnectivity();
      if (mounted) setState(() => _isOnline = r.first != ConnectivityResult.none);
    } catch (_) {}
    widget.type == 'pdf' ? await _initPdf() : await _initVideo();
  }

  // ─── VIDEO ─────────────────────────────────────────────────────────
  Future<void> _initVideo() async {
    if (_isWeb) { if (mounted) setState(() => _isLoading = false); return; }
    final url = ref.read(moduleDataProvider)?.videoUrl ?? '';
    if (url.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _error = 'Video manzili kiritilmagan'; });
      return;
    }
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted) setState(() => _isLoading = false); },
        onWebResourceError: (_) {
          if (mounted) setState(() { _isLoading = false; _error = 'Video yuklanmadi.'; });
        },
      ));

    if (_isYt(url)) {
      final id = extractYoutubeId(url);
      if (id.isEmpty) {
        if (mounted) setState(() { _isLoading = false; _error = 'YouTube ID topilmadi'; });
        return;
      }
      // Custom player — YouTube IFrame API srcdoc orqali
      ctrl.loadHtmlString(buildCustomYoutubeHtml(id), baseUrl: 'https://www.youtube.com');
    } else {
      // Drive: /preview
      ctrl.loadRequest(Uri.parse(MediaPdfHelper.buildDrivePreviewUrl(url)));
    }
    if (mounted) setState(() => _videoWeb = ctrl);
  }

  // ─── PDF ───────────────────────────────────────────────────────────
  Future<void> _initPdf() async {
    if (_isWeb) { if (mounted) setState(() => _isLoading = false); return; }
    final url = ref.read(moduleDataProvider)?.pdfUrl ?? '';
    if (url.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _error = 'PDF manzili kiritilmagan'; });
      return;
    }
    // 1. Cache → pdfx
    final cacheFile = await MediaPdfHelper.getCacheFile(url);
    if (await cacheFile.exists() && await cacheFile.length() > 1024) {
      try {
        final c = PdfController(document: PdfDocument.openFile(cacheFile.path));
        if (mounted) setState(() { _pdfCtrl = c; _isPdfNative = true; _isLoading = false; });
        if (_isOnline) _downloadPdf();
        return;
      } catch (_) { await cacheFile.delete(); }
    }
    // 2. WebView /preview (darhol)
    _initPdfWebView(url);
    // 3. Fonda yuklab olish
    if (_isOnline) _downloadPdf();
  }

  void _initPdfWebView(String url) {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF525659))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted && !_isPdfNative) setState(() => _isLoading = false); },
        onWebResourceError: (_) {
          if (mounted && !_isPdfNative) setState(() { _isLoading = false; _error = 'PDF yuklanmadi.'; });
        },
      ))
      ..loadRequest(Uri.parse(MediaPdfHelper.buildDrivePreviewUrl(url)));
    if (mounted && !_isPdfNative) setState(() => _pdfWeb = c);
  }

  Future<void> _downloadPdf() async {
    final url = ref.read(moduleDataProvider)?.pdfUrl ?? '';
    if (url.isEmpty) return;
    final file = await MediaPdfHelper.getCacheFile(url);
    final ok = await MediaPdfHelper.downloadPdf(
        MediaPdfHelper.buildDriveDownloadUrl(url), file);
    if (!ok || !mounted) return;
    try {
      final c = PdfController(document: PdfDocument.openFile(file.path));
      if (mounted) setState(() {
        _pdfCtrl?.dispose();
        _pdfCtrl = c;
        _isPdfNative = true;
        _pdfWeb = null;
      });
    } catch (_) {}
  }

  // ─── FULLSCREEN & ROTATE ───────────────────────────────────────────
  void _toggleFs() {
    final fs = ref.read(isFullScreenProvider);
    ref.read(isFullScreenProvider.notifier).state = !fs;
    if (!fs) {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _toggleRotate() {
    setState(() => _isPdfLandscape = !_isPdfLandscape);
    SystemChrome.setPreferredOrientations(_isPdfLandscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    _conSub.cancel();
    _pdfCtrl?.dispose();
    if (_isWeb && widget.type == 'pdf') setWebZoomable(false);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─── BUILD ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isFs = ref.watch(isFullScreenProvider);
    if (isFs) return _buildFullScreen();
    final data = ref.watch(moduleDataProvider);
    if (data == null) return const Center(child: Text("Ma'lumot yo'q"));
    final url = widget.type == 'pdf' ? data.pdfUrl : data.videoUrl;
    if (url.isEmpty) {
      return Center(
          child: Text(widget.type == 'pdf' ? 'Chizma kiritilmagan' : 'Video kiritilmagan',
              style: const TextStyle(color: AppColors.textGray)));
    }
    return Column(children: [
      const SizedBox(height: 10),
      _buildTopBar(data.artikul),
      if (widget.type == 'pdf' && _isPdfNative)
        Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('$_pdfPage / $_pdfTotal',
                style: const TextStyle(color: AppColors.textGray, fontSize: 12))),
      if (widget.type == 'pdf' && !_isPdfNative && _pdfWeb != null && _isOnline)
        Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textGray)),
              const SizedBox(width: 6),
              const Text('Native rejim yuklanmoqda...',
                  style: TextStyle(color: AppColors.textGray, fontSize: 11)),
            ])),
      Expanded(child: _buildContent(url, data)),
    ]);
  }

  Widget _buildTopBar(String artikul) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        Expanded(child: Text(artikul,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
        if (!_isOnline)
          const Padding(padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.wifi_off, color: Colors.orange, size: 18)),
        if (widget.type == 'pdf' && _isPdfNative)
          IconButton(
              onPressed: _toggleRotate,
              icon: Icon(
                  _isPdfLandscape ? Icons.stay_primary_portrait : Icons.stay_primary_landscape,
                  color: AppColors.primary),
              tooltip: 'Burish'),
        IconButton(onPressed: _toggleFs, icon: const Icon(Icons.fullscreen)),
        Icon(widget.type == 'video' ? Icons.video_library : Icons.picture_as_pdf,
            color: widget.type == 'video' ? AppColors.accent : AppColors.danger),
      ]),
    );
  }

  Widget _buildContent(String url, dynamic data) {
    // Hali hech narsa yo'q
    if (_isLoading && _videoWeb == null && _pdfWeb == null && _pdfCtrl == null) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: AppColors.accent),
        SizedBox(height: 12),
        Text('Yuklanmoqda...', style: TextStyle(color: AppColors.textGray)),
      ]));
    }
    // Xato holati
    if (_error != null && _pdfWeb == null && _pdfCtrl == null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(_isOnline ? Icons.error_outline : Icons.wifi_off,
            color: _isOnline ? AppColors.danger : Colors.orange, size: 48),
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textGray, height: 1.5)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () {
            setState(() { _isLoading = true; _error = null; _isPdfNative = false; _pdfWeb = null; });
            widget.type == 'pdf' ? _initPdf() : _initVideo();
          },
          icon: const Icon(Icons.refresh), label: const Text('Qayta urinish'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent)),
      ])));
    }

    // ── VIDEO ──────────────────────────────────────────────────────
    if (widget.type == 'video') {
      if (_isWeb) return buildWebIframe(_buildEmbedUrl(url), true, key: ValueKey('vid_${data.artikul}'));
      if (_videoWeb != null) return _buildVideoStack(url);
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    // ── PDF ────────────────────────────────────────────────────────
    // Web: Drive /preview iframe (GitHub Pages)
    if (_isWeb) return buildWebIframe(url, false, key: ValueKey('pdf_${data.artikul}'));
    // Mobile: native pdfx (cache dan)
    if (_isPdfNative && _pdfCtrl != null) {
      return PdfView(
          controller: _pdfCtrl!,
          scrollDirection: Axis.vertical,
          onDocumentLoaded: (d) { if (mounted) setState(() => _pdfTotal = d.pagesCount); },
          onPageChanged: (p) { if (mounted) setState(() => _pdfPage = p); });
    }
    // Mobile: WebView /preview (fallback)
    if (_pdfWeb != null) return _buildPdfWebStack();
    return const Center(child: CircularProgressIndicator(color: AppColors.accent));
  }

  /// Drive video WebView — o'ng-tepa + pastki pardalar
  Widget _buildVideoStack(String url) {
    final isDrive = _isDrive(url);
    return Stack(children: [
      WebViewWidget(controller: _videoWeb!),
      // O'ng-tepa: "Tashqarida ochish" tugmasini bloklash
      Positioned(top: 0, right: 0,
          child: PointerInterceptor(
              child: Container(width: 70, height: 70, color: Colors.transparent))),
      // Drive pastki bar
      if (isDrive)
        Positioned(bottom: 0, left: 0, right: 0,
            child: PointerInterceptor(
                child: Container(height: 44, color: Colors.transparent))),
      // YouTube pastki-chap logo
      if (!isDrive)
        Positioned(bottom: 0, left: 0,
            child: PointerInterceptor(
                child: Container(width: 160, height: 50, color: Colors.transparent))),
    ]);
  }

  /// PDF WebView — o'ng-tepa "Open with" tugmasini bloklash
  Widget _buildPdfWebStack() {
    return Stack(children: [
      WebViewWidget(controller: _pdfWeb!),
      Positioned(top: 0, right: 0,
          child: PointerInterceptor(
              child: Container(width: 65, height: 65, color: Colors.transparent))),
    ]);
  }

  Widget _buildFullScreen() {
    final data = ref.read(moduleDataProvider);
    if (data == null) return const SizedBox();
    final url = widget.type == 'pdf' ? data.pdfUrl : data.videoUrl;
    return Container(color: Colors.black, child: Stack(children: [
      _buildContent(url, data),
      SafeArea(child: Padding(padding: const EdgeInsets.all(12),
          child: PointerInterceptor(child: IconButton(onPressed: _toggleFs,
              icon: const CircleAvatar(backgroundColor: Colors.black54,
                  child: Icon(Icons.close, color: Colors.white)))))),
    ]));
  }

  String _buildEmbedUrl(String url) {
    if (_isYt(url)) {
      final id = extractYoutubeId(url);
      return 'https://www.youtube.com/embed/$id?autoplay=0&rel=0&modestbranding=1&controls=1';
    }
    return MediaPdfHelper.buildDrivePreviewUrl(url);
  }
}