import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

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
  VideoPlayerController? _videoCtrl;
  ChewieController? _chewieCtrl;
  double? _dlProgress;
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
    if (_isWeb) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final url = ref.read(moduleDataProvider)?.videoUrl ?? '';
    if (url.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _error = 'Video manzili kiritilmagan'; });
      return;
    }

    // 1. Cache tekshirish (faqat G-Drive uchun)
    if (_isDrive(url)) {
      final cf = await _getCacheFile(url, isVideo: true);
      if (await cf.exists() && await cf.length() > 1024 * 1024) {
        // Keshdan o'qishdan oldin fayl haqiqiy video ekanligini tekshirish
        if (await _isValidVideoFile(cf)) {
          await _initChewiePlayer(cf);
          if (_isOnline) _tryDownloadVideo(); // Yangi versiya bo'lsa yangilash
          return;
        } else {
          // Yaroqsiz fayl — o'chirib qayta yuklab olish
          await cf.delete();
        }
      }
    }

    // 2. YouTube
    final id = extractYoutubeId(url);
    if (id.isNotEmpty) {
      _loadYoutubePlayer(id);
      return;
    }

    // 3. G-Drive preview (WebView orqali) + fon yuklash
    _loadDrivePreview(MediaPdfHelper.buildDrivePreviewUrl(url));
    if (_isOnline) _tryDownloadVideo();
  }

  /// Fayl haqiqiy video (MP4/MKV/AVI) ekanligini magic bytes bilan tekshirish
  Future<bool> _isValidVideoFile(File file) async {
    try {
      final bytes = await file.openRead(0, 12).first;
      if (bytes.length < 8) return false;

      // MP4: offset 4-7 da "ftyp" yoki "moov" yoki "mdat"
      final sig4 = String.fromCharCodes(bytes.sublist(4, 8));
      if (sig4 == 'ftyp' || sig4 == 'moov' || sig4 == 'mdat' || sig4 == 'wide') {
        return true;
      }
      // MKV: 1A 45 DF A3
      if (bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3) {
        return true;
      }
      // AVI: "RIFF"
      if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Lokal keshdan .mp4 ni video_player va chewie yordamida ochish
  Future<void> _initChewiePlayer(File file) async {
    // Eski controllerlarni tozalash
    _chewieCtrl?.dispose();
    _chewieCtrl = null;
    await _videoCtrl?.dispose();
    _videoCtrl = null;

    _videoCtrl = VideoPlayerController.file(file);
    try {
      await _videoCtrl!.initialize().timeout(const Duration(seconds: 15));

      if (!mounted) return;

      _chewieCtrl = ChewieController(
        videoPlayerController: _videoCtrl!,
        autoPlay: true,
        looping: false,
        allowFullScreen: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.accent,
          handleColor: AppColors.accent,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.white30,
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
                const SizedBox(height: 8),
                Text(errorMessage,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final cf = await _getCacheFile(
                        ref.read(moduleDataProvider)?.videoUrl ?? '',
                        isVideo: true);
                    if (await cf.exists()) await cf.delete();
                    setState(() { _isLoading = true; _error = null; _chewieCtrl?.dispose(); _chewieCtrl = null; _videoCtrl?.dispose(); _videoCtrl = null; _dlDone = false; });
                    _initVideo();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
                  child: const Text('Qayta urinish'),
                ),
              ],
            ),
          );
        },
      );

      if (mounted) setState(() { _isLoading = false; _dlDone = true; });
    } catch (e) {
      // Fayl yaroqsiz — o'chirib xato ko'rsatish
      try { await file.delete(); } catch (_) {}
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Video ijro etilmadi. Qayta yuklab olinadi...';
        });
        // 2 sekunddan keyin qayta urinish
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          setState(() { _error = null; _isLoading = true; });
          _initVideo();
        }
      }
    }
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

  /// ─── BUG FIX: Virus-scan bypass + progress + magic bytes tekshiruvi ───
  Future<void> _tryDownloadVideo() async {
    final url = ref.read(moduleDataProvider)?.videoUrl ?? '';
    if (!_isDrive(url)) return;

    final file = await _getCacheFile(url, isVideo: true);
    if (await file.exists() &&
        await file.length() > 1024 * 1024 &&
        await _isValidVideoFile(file)) {
      if (mounted) setState(() { _dlDone = true; _dlProgress = null; });
      // Allaqachon keshda — native playerga o'tish
      if (_videoWeb != null && _chewieCtrl == null) {
        final wCtrl = _videoWeb;
        setState(() { _videoWeb = null; _isLoading = true; });
        if (wCtrl != null) {
          try { await wCtrl.loadRequest(Uri.parse('about:blank')); } catch (_) {}
        }
        await _initChewiePlayer(file);
      }
      return;
    }

    try {
      if (mounted) setState(() => _dlProgress = 0.0);

      var dlUrl = MediaPdfHelper.buildDriveDownloadUrl(url);

      // ── 1-qadam: Virus scan sahifasini bypass qilish ──
      // http.get bilan boshlang'ich so'rov
      var res = await http.get(Uri.parse(dlUrl))
          .timeout(const Duration(seconds: 30));
      final ct = res.headers['content-type'] ?? '';

      if (ct.contains('text/html')) {
        final body = res.body;
        // Google Drive virus scan redirect parametrlarini izlash
        final uuidM = RegExp(r'uuid=([^&>\s"]+)').firstMatch(body);
        final confM = RegExp(r'confirm=([^&>\s"]+)').firstMatch(body);
        final actM  = RegExp(r'action="([^"]+)"').firstMatch(body);

        if (uuidM != null) {
          dlUrl = '$dlUrl&uuid=${uuidM.group(1)}';
        } else if (confM != null && confM.group(1) != 't') {
          dlUrl = '$dlUrl&confirm=${confM.group(1)}';
        } else if (actM != null) {
          dlUrl = actM.group(1)!.replaceAll('&amp;', '&');
        } else {
          // confirm=t har doim ishlaydi
          dlUrl = '$dlUrl&confirm=t';
        }
      }

      // ── 2-qadam: Streaming download (progress bilan) ──
      final request = await HttpClient().getUrl(Uri.parse(dlUrl));
      request.headers.set('User-Agent', 'Mozilla/5.0');
      final response = await request.close();

      // HTML kelsa — virus scan bypass ishlamadi
      final respCt = response.headers.contentType?.mimeType ?? '';
      if (respCt.contains('html') || respCt.contains('text')) {
        if (mounted) setState(() => _dlProgress = null);
        return;
      }

      final total = response.contentLength;
      var received = 0;

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

      // ── 3-qadam: Fayl validatsiyasi ──
      if (await file.length() < 512 * 1024 || !await _isValidVideoFile(file)) {
        await file.delete();
        if (mounted) setState(() => _dlProgress = null);
        return;
      }

      // ── 4-qadam: Muvaffaqiyatli — native playerga o'tish ──
      if (mounted) {
        setState(() { _dlProgress = null; _dlDone = true; });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Video keshga yuklandi! Oflayn ko\'rinadi.'),
            backgroundColor: AppColors.accent,
            duration: Duration(seconds: 3),
          ),
        );

        // WebView o'rniga native Chewie playerga o'tish
        if (_videoWeb != null || _chewieCtrl == null) {
          final wCtrl = _videoWeb;
          setState(() { _videoWeb = null; _isLoading = true; });
          if (wCtrl != null) {
            try { await wCtrl.loadRequest(Uri.parse('about:blank')); } catch (_) {}
          }
          await _initChewiePlayer(file);
        }
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
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
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
    if (_isLoading &&
        _videoWeb == null &&
        _pdfWeb == null &&
        _pdfCtrl == null &&
        _chewieCtrl == null) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: AppColors.accent), SizedBox(height: 12),
        Text('Yuklanmoqda...', style: TextStyle(color: AppColors.textGray)),
      ]));
    }
    if (_error != null && _pdfWeb == null && _pdfCtrl == null && _chewieCtrl == null) {
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
            setState(() {
              _isLoading = true; _error = null;
              _isPdfNative = false; _pdfWeb = null; _videoWeb = null;
              _chewieCtrl?.dispose(); _chewieCtrl = null;
              _videoCtrl?.dispose(); _videoCtrl = null;
            });
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
      if (_chewieCtrl != null) return Chewie(controller: _chewieCtrl!);
      if (_videoWeb != null) return _buildVideoWebStack();
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    if (_isWeb) return buildWebIframe(url, false, key: ValueKey('pdf_${data.artikul}'));
    if (_isPdfNative && _pdfCtrl != null) {
      return PdfView(
          controller: _pdfCtrl!,
          scrollDirection: Axis.vertical,
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

  Widget _buildVideoWebStack() {
    return Stack(children: [
      WebViewWidget(controller: _videoWeb!),
      // Yuklangunicha ko'rinadigan "Pop-out" G-Drive tugmasini pardalash
      Positioned(top: 0, right: 0,
          child: PointerInterceptor(
              child: Container(width: 80, height: 80, color: Colors.transparent))),
      // Tepada "Open with" chiqib qolmasligi uchun himoya pardasi
      Positioned(bottom: 0, left: 0, right: 0,
          child: PointerInterceptor(
              child: Container(height: 50, color: Colors.transparent))),
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