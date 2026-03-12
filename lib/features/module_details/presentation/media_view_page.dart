import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/api_repository.dart';
import '../../shell/presentation/shell_page.dart';
import 'media_pdf_helper.dart';
import 'custom_youtube_html.dart';
import 'web_iframe_stub.dart' if (dart.library.html) 'web_iframe.dart';

// ═══════════════════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════════════════

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
  double? _dlProgress; // null = yuklanmayapti, 0.0-1.0
  bool _dlDone = false;

  late final StreamSubscription<List<ConnectivityResult>> _conSub;

  bool _isDrive(String u) => u.contains('drive.google.com');
  bool _isYt(String u) => u.contains('youtu.be') || u.contains('youtube.com');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    _conSub = Connectivity().onConnectivityChanged.listen((r) {
      if (!mounted) return;
      final on = r.isNotEmpty && r.first != ConnectivityResult.none;
      setState(() => _isOnline = on);
      if (widget.type == 'pdf' && on && !_isPdfNative && !_isWeb) _tryDownloadPdf();
      if (widget.type == 'video' && on && !_isWeb) _tryDownloadVideo();
    });
    if (_isWeb && widget.type == 'pdf') setWebZoomable(true);
  }

  Future<void> _init() async {
    try {
      final r = await Connectivity().checkConnectivity();
      if (mounted) setState(() => _isOnline = r.isNotEmpty && r.first != ConnectivityResult.none);
    } catch (_) {}
    widget.type == 'pdf' ? await _initPdf() : await _initVideo();
  }

  WebViewController _newController() {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);
    if (ctrl.platform is AndroidWebViewController) {
      (ctrl.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    return ctrl;
  }

  // ─── VIDEO ──────────────────────────────────────────────────
  Future<void> _initVideo() async {
    if (_isWeb) { if (mounted) setState(() => _isLoading = false); return; }
    final url = ref.read(moduleDataProvider)?.videoUrl ?? '';
    if (url.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _error = 'Video manzili kiritilmagan'; });
      return;
    }

    // 1. Cache tekshirish (faqat G-Drive uchun)
    if (_isDrive(url)) {
      final cf = await _getCacheFile(url, isVideo: true);
      if (await cf.exists() && await cf.length() > 1024 * 1024) {
        _loadLocalVideoHtml(cf.path);
        if (_isOnline) _tryDownloadVideo();
        return;
      }
    }

    // 2. YouTube
    final id = extractYoutubeId(url);
    if (id.isNotEmpty) {
      _loadYoutubePlayer(id);
      return;
    }

    // 3. G-Drive preview (WebView orqali)
    _loadDrivePreview(MediaPdfHelper.buildDrivePreviewUrl(url));
    if (_isOnline) _tryDownloadVideo();
  }

  /// Lokal keshdan .mp4 ni HTML5 video player bilan ochish
  void _loadLocalVideoHtml(String filePath) {
    final html = '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%;height:100%;background:#000;overflow:hidden}
video{width:100%;height:100%;object-fit:contain;display:block}
</style></head><body>
<video controls autoplay playsinline src="file://$filePath"></video>
</body></html>''';
    final ctrl = _newController()
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted) setState(() => _isLoading = false); },
        onWebResourceError: (err) {
          if ((err.isForMainFrame ?? false) && mounted) {
            setState(() { _isLoading = false; _error = 'Video ijro etilmadi.'; });
          }
        },
      ))
      ..loadHtmlString(html, baseUrl: 'file:///');
    if (mounted) setState(() { _videoWeb = ctrl; _dlDone = true; });
  }

  /// YouTube custom player
  void _loadYoutubePlayer(String videoId) {
    final ctrl = _newController()
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted) setState(() => _isLoading = false); },
        onWebResourceError: (err) {
          if ((err.isForMainFrame ?? false) && mounted) {
            setState(() { _isLoading = false; _error = 'YouTube yuklanmadi.'; });
          }
        },
      ))
      ..loadHtmlString(buildCustomYoutubeHtml(videoId), baseUrl: 'https://www.youtube.com');
    if (mounted) setState(() => _videoWeb = ctrl);
  }

  /// G-Drive /preview WebView orqali
  void _loadDrivePreview(String previewUrl) {
    final ctrl = _newController()
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted) setState(() => _isLoading = false); },
        onWebResourceError: (err) {
          if ((err.isForMainFrame ?? false) && mounted) {
            setState(() { _isLoading = false; _error = 'Video yuklanmadi.'; });
          }
        },
      ))
      ..loadRequest(Uri.parse(previewUrl));
    if (mounted) setState(() => _videoWeb = ctrl);
  }

  Future<void> _tryDownloadVideo() async {
    final url = ref.read(moduleDataProvider)?.videoUrl ?? '';
    if (!_isDrive(url)) return;
    final file = await _getCacheFile(url, isVideo: true);
    if (await file.exists() && await file.length() > 1024 * 1024) {
      if (mounted) setState(() { _dlDone = true; _dlProgress = null; });
      return;
    }
    try {
      final dlUrl = MediaPdfHelper.buildDriveDownloadUrl(url);
      final request = await HttpClient().getUrl(Uri.parse(dlUrl));
      final response = await request.close();
      final total = response.contentLength;
      var received = 0;
      if (mounted) setState(() => _dlProgress = 0.0);
      final sink = file.openWrite();
      await response.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() => _dlProgress = received / total);
        }
      }).asFuture();
      await sink.flush();
      await sink.close();
      // Fayl bo'sh yoki noto'g'ri bo'lsa o'chirib tashlash
      if (await file.length() < 1024 * 1024) {
        await file.delete();
        if (mounted) setState(() => _dlProgress = null);
        return;
      }
      if (mounted) {
        setState(() { _dlProgress = null; _dlDone = true; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Video keshga yuklandi! Keyingi safar oflayn ko\'rinadi.'),
            backgroundColor: AppColors.accent,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _dlProgress = null);
    }
  }

  // ─── PDF ────────────────────────────────────────────────────
  Future<void> _initPdf() async {
    if (_isWeb) { if (mounted) setState(() => _isLoading = false); return; }
    final url = ref.read(moduleDataProvider)?.pdfUrl ?? '';
    if (url.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _error = 'PDF manzili kiritilmagan'; });
      return;
    }
    final cf = await MediaPdfHelper.getCacheFile(url);
    if (await cf.exists() && await cf.length() > 1024) {
      try {
        final c = PdfController(document: PdfDocument.openFile(cf.path));
        if (mounted) setState(() { _pdfCtrl = c; _isPdfNative = true; _isLoading = false; });
        if (_isOnline) _tryDownloadPdf();
        return;
      } catch (_) { await cf.delete(); }
    }
    _initPdfWebView(url);
    if (_isOnline) _tryDownloadPdf();
  }

  void _initPdfWebView(String url) {
    final c = _newController()
      ..setBackgroundColor(const Color(0xFF525659))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted && !_isPdfNative) setState(() => _isLoading = false); },
        onWebResourceError: (err) {
          if ((err.isForMainFrame ?? false) && mounted && !_isPdfNative) {
            setState(() { _isLoading = false; _error = 'PDF yuklanmadi.'; });
          }
        },
      ))
      ..loadRequest(Uri.parse(MediaPdfHelper.buildDrivePreviewUrl(url)));
    if (mounted && !_isPdfNative) setState(() => _pdfWeb = c);
  }

  Future<void> _tryDownloadPdf() async {
    final url = ref.read(moduleDataProvider)?.pdfUrl ?? '';
    if (url.isEmpty) return;
    final file = await MediaPdfHelper.getCacheFile(url);
    final ok = await MediaPdfHelper.downloadPdf(MediaPdfHelper.buildDriveDownloadUrl(url), file);
    if (!ok || !mounted) return;
    try {
      final c = PdfController(document: PdfDocument.openFile(file.path));
      if (mounted) setState(() {
        _pdfCtrl?.dispose(); _pdfCtrl = c; _isPdfNative = true; _pdfWeb = null;
      });
    } catch (_) {}
  }

  Future<File> _getCacheFile(String url, {bool isVideo = false}) async {
    final dir = await getTemporaryDirectory();
    final id = MediaPdfHelper.extractDriveId(url);
    final ext = isVideo ? '.mp4' : '.pdf';
    final prefix = isVideo ? 'vid_' : 'pdf_';
    return File('${dir.path}/$prefix${id.isNotEmpty ? id : 'cache'}$ext');
  }

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

  @override
  Widget build(BuildContext context) {
    final isFs = ref.watch(isFullScreenProvider);
    if (isFs) return _buildFullScreen();
    final data = ref.watch(moduleDataProvider);
    if (data == null) return const Center(child: Text("Ma'lumot yo'q"));
    final url = widget.type == 'pdf' ? data.pdfUrl : data.videoUrl;
    if (url.isEmpty) {
      return Center(child: Text(
          widget.type == 'pdf' ? 'Chizma kiritilmagan' : 'Video kiritilmagan',
          style: const TextStyle(color: AppColors.textGray)));
    }
    return Column(children: [
      const SizedBox(height: 10),
      _buildTopBar(data.artikul),
      if (_dlProgress != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(children: [
            const Icon(Icons.download, size: 14, color: AppColors.textGray),
            const SizedBox(width: 6),
            Expanded(child: LinearProgressIndicator(
              value: _dlProgress,
              backgroundColor: Colors.grey.shade300,
              color: AppColors.accent,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(width: 8),
            Text('${((_dlProgress ?? 0) * 100).toInt()}%',
                style: const TextStyle(fontSize: 10, color: AppColors.textGray)),
          ]),
        )
      else if (_dlDone && widget.type == 'video')
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(children: [
            Icon(Icons.offline_pin, size: 14, color: AppColors.accent),
            SizedBox(width: 6),
            Text('Oflayn mavjud', style: TextStyle(fontSize: 10, color: AppColors.accent)),
          ]),
        ),
      if (widget.type == 'pdf' && _isPdfNative)
        Padding(padding: const EdgeInsets.only(bottom: 4),
            child: Text('$_pdfPage / $_pdfTotal',
                style: const TextStyle(color: AppColors.textGray, fontSize: 12))),
      if (widget.type == 'pdf' && !_isPdfNative && _pdfWeb != null && _isOnline)
        Padding(padding: const EdgeInsets.only(bottom: 2),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 10, height: 10,
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
          IconButton(onPressed: _toggleRotate, tooltip: 'Burish',
              icon: Icon(_isPdfLandscape
                  ? Icons.stay_primary_portrait : Icons.stay_primary_landscape,
                  color: AppColors.accent)),
        IconButton(onPressed: _toggleFs, icon: const Icon(Icons.fullscreen)),
        Icon(widget.type == 'video' ? Icons.video_library : Icons.picture_as_pdf,
            color: widget.type == 'video' ? AppColors.accent : AppColors.danger),
      ]),
    );
  }

  Widget _buildContent(String url, dynamic data) {
    if (_isLoading && _videoWeb == null && _pdfWeb == null && _pdfCtrl == null) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: AppColors.accent), SizedBox(height: 12),
        Text('Yuklanmoqda...', style: TextStyle(color: AppColors.textGray)),
      ]));
    }
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
            setState(() { _isLoading = true; _error = null; _isPdfNative = false; _pdfWeb = null; _videoWeb = null; });
            widget.type == 'pdf' ? _initPdf() : _initVideo();
          },
          icon: const Icon(Icons.refresh), label: const Text('Qayta urinish'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent)),
      ])));
    }

    if (widget.type == 'video') {
      if (_isWeb) {
        final id = extractYoutubeId(url);
        final embed = id.isNotEmpty
            ? 'https://www.youtube.com/embed/$id?rel=0&modestbranding=1&controls=1'
            : MediaPdfHelper.buildDrivePreviewUrl(url);
        return buildWebIframe(embed, true, key: ValueKey('vid_${data.artikul}'));
      }
      if (_videoWeb != null) return WebViewWidget(controller: _videoWeb!);
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    if (_isWeb) return buildWebIframe(url, false, key: ValueKey('pdf_${data.artikul}'));
    if (_isPdfNative && _pdfCtrl != null) {
      return PdfView(controller: _pdfCtrl!, scrollDirection: Axis.vertical,
          onDocumentLoaded: (d) { if (mounted) setState(() => _pdfTotal = d.pagesCount); },
          onPageChanged: (p) { if (mounted) setState(() => _pdfPage = p); });
    }
    if (_pdfWeb != null) return _buildPdfWebStack();
    return const Center(child: CircularProgressIndicator(color: AppColors.accent));
  }

  Widget _buildPdfWebStack() {
    return Stack(children: [
      WebViewWidget(controller: _pdfWeb!),
      Positioned(top: 0, right: 0,
          child: PointerInterceptor(
              child: Container(width: 80, height: 80, color: Colors.transparent))),
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
}
