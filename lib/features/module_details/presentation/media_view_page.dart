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

import '../../../core/constants/colors.dart';
import '../providers/module_details_provider.dart';
import 'media_pdf_helper.dart';
import 'iframe_stub.dart' if (dart.library.html) 'web_iframe.dart';

String _ytHtml(String mediaPath, {bool isUrl = false}) => '''<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no">
<style>
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent;font-family:sans-serif}
html,body{width:100%;height:100%;background:#000;overflow:hidden}
#media-container{position:relative;width:100%;height:100%;background:#000;user-select:none}
#player-target{width:100%;height:100%;border:none;display:block}
#absolute-shield{position:absolute;top:0;left:0;width:100%;height:100%;z-index:10;background:transparent;touch-action:none;cursor:pointer}
#shield-gdrive-popout{position:absolute;top:0;right:0;width:80px;height:80px;background:transparent;z-index:15;display:none}
#tap-indicator{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);background:rgba(0,0,0,0.7);color:white;padding:15px 25px;border-radius:10px;font-size:22px;font-weight:bold;opacity:0;transition:opacity 0.2s;z-index:20;pointer-events:none;text-align:center}
#loader{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);width:40px;height:40px;border:3px solid rgba(255,255,255,0.2);border-top-color:#27ae60;border-radius:50%;animation:spin 0.8s linear infinite;z-index:5}
@keyframes spin{to{transform:translate(-50%,-50%) rotate(360deg)}}
#custom-controls{position:absolute;bottom:0;left:0;width:100%;height:50px;background:rgba(20,20,20,0.95);display:none;align-items:center;padding:0 10px;z-index:30;gap:10px}
.control-btn{background:none;border:none;color:white;font-size:20px;cursor:pointer;padding:5px;outline:none;transition:color 0.2s;flex-shrink:0}
#seek-bar{flex:1;cursor:pointer;accent-color:#27ae60;height:5px}
#time-display{color:white;font-size:13px;font-weight:bold;min-width:90px;text-align:center;font-variant-numeric:tabular-nums;flex-shrink:0}
</style></head>
<body>
<div id="media-container">
  <div id="loader"></div>
  <div id="player-target"></div>
  <div id="absolute-shield"></div>
  <div id="shield-gdrive-popout"></div>
  <div id="tap-indicator"></div>
  <div id="custom-controls">
    <button id="play-pause-btn" class="control-btn" onclick="togglePlayPause()">&#9654;</button>
    <div style="flex:1;display:flex;align-items:center;padding:0 5px;">
        <input type="range" id="seek-bar" value="0" step="0.1" style="width:100%;">
    </div>
    <span id="time-display">0:00 / 0:00</span>
  </div>
</div>
<script>
var mediaPath = "\$mediaPath";
var isUrl = \$isUrl;
var playerElement = document.getElementById('player-target');
var shield = document.getElementById('absolute-shield');
var controls = document.getElementById('custom-controls');
var isPlaying = true;
var duration = 0;
var currentTime = 0;
var startX=0, startY=0, startT=0;
var isSwiping=false, swipeDir=null;
var lastClick=0, clickTimer=null;
function init() {
    if (!isUrl) {
       const url = `https://www.youtube.com/embed/\${mediaPath}?controls=0&modestbranding=1&rel=0&enablejsapi=1&autoplay=1&playsinline=1`;
       playerElement.innerHTML = `<iframe id="yt-iframe" src="\${url}" style="width:100%;height:100%;border:none;" allow="autoplay"></iframe>`;
       document.getElementById('loader').style.display='none';
    } else if (mediaPath.includes('drive.google.com')) {
       playerElement.innerHTML = `<iframe src="\${mediaPath}" style="width:100%;height:100%;border:none;" allow="autoplay"></iframe>`;
       document.getElementById('shield-gdrive-popout').style.display='block';
       document.getElementById('loader').style.display='none';
    } else {
       playerElement.innerHTML = `<video id="video-tag" src="\${mediaPath}" style="width:100%;height:100%;" autoplay playsinline></video>`;
       var v = document.getElementById('video-tag');
       v.onloadedmetadata = () => { duration = v.duration; controls.style.display = 'flex'; document.getElementById('loader').style.display='none'; };
       v.ontimeupdate = () => { currentTime = v.currentTime; updateUI(); };
    }
}
function formatTime(sec){ var m=Math.floor(sec/60),s=Math.floor(sec%60); return m+':'+(s<10?'0':'')+s; }
function updateUI() {
    document.getElementById('time-display').innerText = formatTime(currentTime) + ' / ' + formatTime(duration);
    if (duration > 0) { var sb = document.getElementById('seek-bar'); sb.max = duration; sb.value = currentTime; }
}
function togglePlayPause(){
    var v = document.getElementById('video-tag');
    var f = document.getElementById('yt-iframe');
    if (v) { if (v.paused) v.play(); else v.pause(); isPlaying = !v.paused; }
    else if (f) { isPlaying = !isPlaying; f.contentWindow.postMessage(JSON.stringify({event:'command', func:isPlaying?'playVideo':'pauseVideo', args:[]}), '*'); }
    document.getElementById('play-pause-btn').innerHTML = isPlaying ? '&#9646;&#9646;' : '&#9654;';
}
function seekTo(t) {
    var v = document.getElementById('video-tag');
    var f = document.getElementById('yt-iframe');
    if (v) v.currentTime = t; else if (f) f.contentWindow.postMessage(JSON.stringify({event:'command', func:'seekTo', args:[t, true]}), '*');
}
shield.addEventListener('pointerdown', e => { startX = e.clientX; startY = e.clientY; startT = currentTime; isSwiping = false; swipeDir = null; shield.setPointerCapture(e.pointerId); });
shield.addEventListener('pointermove', e => {
    if (e.buttons !== 1) return;
    var dx = e.clientX - startX, dy = e.clientY - startY;
    if (!swipeDir) { if (Math.abs(dx) > 15) swipeDir = 'h'; else if (Math.abs(dy) > 15) swipeDir = 'v'; }
    if (swipeDir === 'h') {
        isSwiping = true;
        var offset = (dx / (shield.clientWidth / 2)) * 30;
        currentTime = Math.max(0, Math.min(duration, startT + offset));
        updateUI();
        showIndicator((offset > 0 ? ">> " : "<< ") + formatTime(currentTime));
    } else if (swipeDir === 'v') {
        isSwiping = true;
        var v = document.getElementById('video-tag');
        var offset = -(dy / (shield.clientHeight / 2)) * 100;
        // Native video pleyer uchun ovozni o'zgartirish
        if (v) {
            var newVol = Math.max(0, Math.min(1, (v.volume || 1) + offset/100));
            v.volume = newVol;
            showIndicator("🔊 " + Math.round(newVol * 100) + "%");
        } else {
            showIndicator(dy < 0 ? "🔊 Ovoz +" : "🔉 Ovoz -");
        }
    }
});
shield.addEventListener('pointerup', e => {
    if (isSwiping) { if (swipeDir === 'h') seekTo(currentTime); hideIndicator(); return; }
    var now = Date.now(), diff = now - lastClick;
    if (diff < 300 && diff > 0) {
        clearTimeout(clickTimer);
        var isR = e.clientX > (shield.clientWidth / 2);
        seekTo(currentTime + (isR ? 5 : -5));
        showIndicator(isR ? "+5s" : "-5s");
        setTimeout(hideIndicator, 600);
        lastClick = 0;
    } else { lastClick = now; clickTimer = setTimeout(togglePlayPause, 300); }
});
function showIndicator(txt) { var ind = document.getElementById('tap-indicator'); ind.innerText = txt; ind.style.opacity = '1'; }
function hideIndicator() { document.getElementById('tap-indicator').style.opacity = '0'; }
window.addEventListener('message', e => {
    if (e.origin !== "https://www.youtube.com") return;
    try {
        var d = JSON.parse(e.data);
        if (d.event === 'infoDelivery' && d.info) {
            if (d.info.duration) { duration = d.info.duration; controls.style.display = 'flex'; }
            if (d.info.currentTime) { currentTime = d.info.currentTime; updateUI(); }
        }
    } catch(err) {}
});
init();
</script>
</body></html>''';

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
  PdfController? _pdfCtrl;
  WebViewController? _pdfWeb;
  bool _isPdfNative = false;
  int _pdfPage = 1, _pdfTotal = 1;
  bool _isPdfLandscape = false;
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
      (ctrl.platform as AndroidWebViewController).setMediaPlaybackRequiresUserGesture(false);
    }
    return ctrl;
  }

  Future<void> _initVideo() async {
    if (_isWeb) { if (mounted) setState(() => _isLoading = false); return; }
    final url = ref.read(moduleDataProvider)?.videoUrl ?? '';
    if (url.isEmpty) { if (mounted) setState(() { _isLoading = false; _error = 'Video manzili kiritilmagan'; }); return; }
    if (_isDrive(url)) {
      final cf = await _cacheFile(url, isVideo: true);
      if (await cf.exists() && await cf.length() > 1024 * 1024) { 
        _loadVideoHtml(cf.path, isUrl: true);
        if (_isOnline) _tryDownloadVideo();
        return;
      }
    }
    final id = _isYt(url) ? _ytId(url) : '';
    if (id.isNotEmpty) _loadVideoHtml(id, isUrl: false);
    else _loadVideoHtml(_previewUrl(url), isUrl: true);
    if (_isOnline && _isDrive(url)) _tryDownloadVideo();
  }

  void _loadVideoHtml(String pathOrId, {required bool isUrl}) {
    final ctrl = _newController()
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted) setState(() => _isLoading = false); },
        onWebResourceError: (err) { if ((err.isForMainFrame ?? false) && mounted) setState(() { _isLoading = false; _error = 'Video yuklanmadi.'; }); },
      ))
      ..loadHtmlString(_ytHtml(pathOrId, isUrl: isUrl), baseUrl: isUrl ? null : 'https://www.youtube.com');
    if (mounted) setState(() => _videoWeb = ctrl);
  }

  Future<void> _tryDownloadVideo() async {
    final url = ref.read(moduleDataProvider)?.videoUrl ?? '';
    if (!_isDrive(url)) return;
    final file = await _cacheFile(url, isVideo: true);
    await _downloadPdfFile(_downloadUrl(url), file);
  }

  Future<void> _initPdf() async {
    if (_isWeb) { if (mounted) setState(() => _isLoading = false); return; }
    final url = ref.read(moduleDataProvider)?.pdfUrl ?? '';
    if (url.isEmpty) { if (mounted) setState(() { _isLoading = false; _error = 'PDF manzili kiritilmagan'; }); return; }
    final cf = await _cacheFile(url);
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
        onWebResourceError: (err) { if ((err.isForMainFrame ?? false) && mounted && !_isPdfNative) setState(() { _isLoading = false; _error = 'PDF yuklanmadi.'; }); },
      ))
      ..loadRequest(Uri.parse(_previewUrl(url)));
    if (mounted && !_isPdfNative) setState(() => _pdfWeb = c);
  }

  Future<void> _tryDownloadPdf() async {
    final url = ref.read(moduleDataProvider)?.pdfUrl ?? '';
    if (url.isEmpty) return;
    final file = await _cacheFile(url);
    final ok = await _downloadPdfFile(_downloadUrl(url), file);
    if (!ok || !mounted) return;
    try {
      final c = PdfController(document: PdfDocument.openFile(file.path));
      if (mounted) setState(() { _pdfCtrl?.dispose(); _pdfCtrl = c; _isPdfNative = true; _pdfWeb = null; });
    } catch (_) {}
  }

  Future<File> _cacheFile(String url, {bool isVideo = false}) async {
    final dir = await getTemporaryDirectory();
    final id = _driveId(url);
    final ext = isVideo ? '.mp4' : '.pdf';
    final prefix = isVideo ? 'vid_' : 'pdf_';
    return File('${dir.path}/\${prefix}\${id.isNotEmpty ? id : 'cache'}\${ext}');
  }

  void _toggleFs() {
    final fs = ref.read(isFullScreenProvider);
    ref.read(isFullScreenProvider.notifier).state = !fs;
    if (!fs) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _toggleRotate() {
    setState(() => _isPdfLandscape = !_isPdfLandscape);
    SystemChrome.setPreferredOrientations(_isPdfLandscape ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : [DeviceOrientation.portraitUp]);
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
    if (url.isEmpty) { return Center(child: Text(widget.type == 'pdf' ? 'Chizma kiritilmagan' : 'Video kiritilmagan', style: const TextStyle(color: AppColors.textGray))); }
    return Column(children: [
      const SizedBox(height: 10),
      _buildTopBar(data.artikul),
      if (widget.type == 'pdf' && _isPdfNative) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('\$_pdfPage / \$_pdfTotal', style: const TextStyle(color: AppColors.textGray, fontSize: 12))),
      if (widget.type == 'pdf' && !_isPdfNative && _pdfWeb != null && _isOnline) Padding(padding: const EdgeInsets.only(bottom: 2), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textGray)),
        const SizedBox(width: 6),
        const Text('Native rejim yuklanmoqda...', style: TextStyle(color: AppColors.textGray, fontSize: 11)),
      ])),
      Expanded(child: _buildContent(url, data)),
    ]);
  }

  Widget _buildTopBar(String artikul) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(children: [
      Expanded(child: Text(artikul, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
      if (!_isOnline) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.wifi_off, color: Colors.orange, size: 18)),
      if (widget.type == 'pdf' && _isPdfNative) IconButton(onPressed: _toggleRotate, tooltip: 'Burish', icon: Icon(_isPdfLandscape ? Icons.stay_primary_portrait : Icons.stay_primary_landscape, color: AppColors.primary)),
      IconButton(onPressed: _toggleFs, icon: const Icon(Icons.fullscreen)),
      Icon(widget.type == 'video' ? Icons.video_library : Icons.picture_as_pdf, color: widget.type == 'video' ? AppColors.accent : AppColors.danger),
    ]));
  }

  Widget _buildContent(String url, dynamic data) {
    if (_isLoading && _videoWeb == null && _pdfWeb == null && _pdfCtrl == null) { return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [ CircularProgressIndicator(color: AppColors.accent), SizedBox(height: 12), Text('Yuklanmoqda...', style: TextStyle(color: AppColors.textGray)) ])); }
    if (_error != null && _pdfWeb == null && _pdfCtrl == null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(_isOnline ? Icons.error_outline : Icons.wifi_off, color: _isOnline ? AppColors.danger : Colors.orange, size: 48),
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textGray, height: 1.5)),
        const SizedBox(height: 20),
        ElevatedButton.icon(onPressed: () { setState(() { _isLoading = true; _error = null; _isPdfNative = false; _pdfWeb = null; _videoWeb = null; }); widget.type == 'pdf' ? _initPdf() : _initVideo(); }, icon: const Icon(Icons.refresh), label: const Text('Qayta urinish'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent)),
      ])));
    }
    if (widget.type == 'video') {
      if (_isWeb) {
        final embed = _isYt(url) ? 'https://www.youtube.com/embed/\${_ytId(url)}?rel=0&modestbranding=1&controls=1' : _previewUrl(url);
        return buildWebIframe(embed, true, key: ValueKey('vid_\${data.artikul}'));
      }
      if (_videoWeb != null) return WebViewWidget(controller: _videoWeb!);
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_isWeb) return buildWebIframe(url, false, key: ValueKey('pdf_\${data.artikul}'));
    if (_isPdfNative && _pdfCtrl != null) { return PdfView(controller: _pdfCtrl!, scrollDirection: Axis.vertical, onDocumentLoaded: (d) { if (mounted) setState(() => _pdfTotal = d.pagesCount); }, onPageChanged: (p) { if (mounted) setState(() => _pdfPage = p); }); }
    if (_pdfWeb != null) return _buildPdfWebStack();
    return const Center(child: CircularProgressIndicator(color: AppColors.accent));
  }

  Widget _buildPdfWebStack() {
    return Stack(children: [
      WebViewWidget(controller: _pdfWeb!),
      Positioned(top: 0, right: 0, child: PointerInterceptor(child: Container(width: 80, height: 80, color: Colors.transparent))),
    ]);
  }

  Widget _buildFullScreen() {
    final data = ref.read(moduleDataProvider);
    if (data == null) return const SizedBox();
    final url = widget.type == 'pdf' ? data.pdfUrl : data.videoUrl;
    return Container(color: Colors.black, child: Stack(children: [
      _buildContent(url, data),
      SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: PointerInterceptor(child: IconButton(onPressed: _toggleFs, icon: const CircleAvatar(backgroundColor: Colors.black54, child: Icon(Icons.close, color: Colors.white)))))),
    ]));
  }
}
