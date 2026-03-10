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
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../../data/repositories/api_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../shell/presentation/shell_page.dart';
import 'web_iframe_stub.dart' if (dart.library.html) 'web_iframe.dart';

// ═══════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════

String _driveId(String url) =>
    RegExp(r'[-\w]{25,}').firstMatch(url)?.group(0) ?? '';

String _previewUrl(String url) {
  final id = _driveId(url);
  return id.isNotEmpty ? 'https://drive.google.com/file/d/$id/preview' : url;
}

String _downloadUrl(String url) {
  final id = _driveId(url);
  return id.isNotEmpty
      ? 'https://drive.google.com/uc?export=download&confirm=t&id=$id'
      : url;
}

String _ytId(String url) {
  if (url.contains('youtu.be/')) return url.split('youtu.be/')[1].split('?')[0];
  if (url.contains('youtube.com/watch')) return Uri.parse(url).queryParameters['v'] ?? '';
  if (url.contains('youtube.com/embed/')) return url.split('youtube.com/embed/')[1].split('?')[0];
  return '';
}

Future<File> _cacheFile(String url) async {
  final dir = await getTemporaryDirectory();
  final id = _driveId(url);
  return File('${dir.path}/${id.isNotEmpty ? 'pdf_$id.pdf' : 'pdf_cache.pdf'}');
}

Future<bool> _downloadPdfFile(String url, File file) async {
  try {
    var res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    final ct = res.headers['content-type'] ?? '';
    if (ct.contains('text/html')) {
      final body = res.body;
      final uuidM = RegExp(r'uuid=([^&>\s]+)').firstMatch(body);
      final confM = RegExp(r'confirm=([^&>\s]+)').firstMatch(body);
      final actM  = RegExp(r'action="([^"]+)"').firstMatch(body);
      String newUrl = url;
      if (uuidM != null) {
        newUrl = '$url&uuid=${uuidM.group(1)}';
      } else if (confM != null && confM.group(1) != 't') {
        newUrl = '$url&confirm=${confM.group(1)}';
      } else if (actM != null) {
        newUrl = actM.group(1)!.replaceAll('&amp;', '&');
      }
      if (newUrl != url) {
        res = await http.get(Uri.parse(newUrl)).timeout(const Duration(seconds: 60));
      }
    }
    if (res.statusCode == 200 && res.bodyBytes.length > 1024) {
      final b = res.bodyBytes;
      if (b.length >= 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) {
        await file.writeAsBytes(b);
        return true;
      }
    }
  } catch (_) {}
  return false;
}

// ═══════════════════════════════════════════════════════════════
// YOUTUBE CUSTOM PLAYER HTML
// Reference: custom_player.html + custom_player.js
// Swipe-left/right = vaqt | Swipe-up/down = ovoz
// Double-tap = ±10s | Single-tap = play/pause
// ═══════════════════════════════════════════════════════════════
String _ytHtml(String videoId) => '''<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no">
<style>
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent;font-family:sans-serif}
html,body{width:100%;height:100%;background:#000;overflow:hidden}
#video-container{position:relative;width:100%;height:100%;background:#000;user-select:none}
#yt-player{width:100%;height:100%;pointer-events:none;border:none;display:block}
#absolute-shield{position:absolute;top:0;left:0;width:100%;height:calc(100% - 50px);z-index:10;background:transparent;touch-action:none;cursor:pointer}
#tap-indicator{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);background:rgba(0,0,0,0.7);color:white;padding:15px 25px;border-radius:10px;font-size:22px;font-weight:bold;opacity:0;transition:opacity 0.2s;z-index:15;pointer-events:none;text-align:center}
#loader{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);width:40px;height:40px;border:3px solid rgba(255,255,255,0.2);border-top-color:#27ae60;border-radius:50%;animation:spin 0.8s linear infinite;z-index:5}
@keyframes spin{to{transform:translate(-50%,-50%) rotate(360deg)}}
#custom-controls{position:absolute;bottom:0;left:0;width:100%;height:50px;background:rgba(20,20,20,0.95);display:flex;align-items:center;padding:0 10px;z-index:20;gap:10px}
.control-btn{background:none;border:none;color:white;font-size:20px;cursor:pointer;padding:5px;outline:none;transition:color 0.2s;flex-shrink:0}
.control-btn:active{color:#27ae60}
#seek-bar{flex:1;cursor:pointer;accent-color:#27ae60;height:5px}
#time-display{color:white;font-size:13px;font-weight:bold;min-width:90px;text-align:center;font-variant-numeric:tabular-nums;flex-shrink:0}
#settings-menu{position:absolute;bottom:60px;right:10px;background:rgba(20,20,20,0.95);color:white;padding:15px;border-radius:8px;z-index:25;display:none;min-width:180px;box-shadow:0 5px 15px rgba(0,0,0,0.5)}
.settings-row{display:flex;justify-content:space-between;align-items:center;margin-bottom:15px}
.settings-row:last-child{margin-bottom:0}
.settings-row label{font-size:13px}
.settings-row select{background:#333;color:white;border:1px solid #555;border-radius:4px;padding:5px;outline:none;font-size:12px}
</style></head>
<body>
<div id="video-container">
  <div id="loader"></div>
  <div id="yt-player"></div>
  <div id="absolute-shield"></div>
  <div id="tap-indicator"></div>
  <div id="settings-menu">
    <div class="settings-row"><label>Tezlik:</label>
      <select id="speed-select" onchange="changeSpeed(this.value)">
        <option value="0.5">0.5x</option><option value="0.75">0.75x</option>
        <option value="1" selected>Normal</option><option value="1.25">1.25x</option>
        <option value="1.5">1.5x</option><option value="2">2x</option></select></div>
    <div class="settings-row"><label>Sifat:</label>
      <select id="quality-select" onchange="changeQuality(this.value)"><option value="default">Avto</option></select></div>
  </div>
  <div id="custom-controls">
    <button id="play-pause-btn" class="control-btn" onclick="togglePlayPause()">&#9654;</button>
    <input type="range" id="seek-bar" value="0" step="0.1">
    <span id="time-display">0:00 / 0:00</span>
    <button class="control-btn" onclick="toggleSettings()">&#9881;</button>
  </div>
</div>
<script>
// YouTube IFrame API yuklash
var tag=document.createElement('script');
tag.src="https://www.youtube.com/iframe_api";
document.head.appendChild(tag);

var player,updater,isDraggingBar=false;
var clickTimer=null,lastClickTime=0;
var isSwiping=false,swipeDirection=null;
var startX=0,startY=0,startVideoTime=0,startVolume=0;

function onYouTubeIframeAPIReady(){
  player=new YT.Player('yt-player',{
    height:'100%',width:'100%',videoId:'$videoId',
    playerVars:{controls:0,disablekb:1,rel:0,modestbranding:1,playsinline:1,iv_load_policy:3,fs:0},
    events:{onReady:onPlayerReady,onStateChange:onPlayerStateChange}
  });
}

function onPlayerReady(event){
  document.getElementById('loader').style.display='none';
  event.target.playVideo();
  updateTime();
  populateQualities();
}

function onPlayerStateChange(event){
  var btn=document.getElementById('play-pause-btn');
  if(event.data===YT.PlayerState.PLAYING){
    btn.innerHTML='&#9646;&#9646;';
    updater=setInterval(updateTime,500);
  }else{
    btn.innerHTML='&#9654;';
    clearInterval(updater);
  }
}

function togglePlayPause(){
  if(!player||typeof player.getPlayerState!=='function')return;
  if(player.getPlayerState()===YT.PlayerState.PLAYING)player.pauseVideo();
  else player.playVideo();
}

function formatTime(sec){
  var m=Math.floor(sec/60),s=Math.floor(sec%60);
  return m+':'+(s<10?'0':'')+s;
}

function updateTime(){
  if(!player||isDraggingBar||isSwiping)return;
  var current=player.getCurrentTime()||0,total=player.getDuration()||0;
  document.getElementById('time-display').innerText=formatTime(current)+' / '+formatTime(total);
  if(total>0){var sb=document.getElementById('seek-bar');sb.max=total;sb.value=current;}
}

var seekBar=document.getElementById('seek-bar');
seekBar.addEventListener('input',function(){
  isDraggingBar=true;
  document.getElementById('time-display').innerText=formatTime(this.value)+' / '+formatTime(player?player.getDuration():0);
});
seekBar.addEventListener('change',function(){
  if(player)player.seekTo(this.value,true);
  isDraggingBar=false;
});

// AQLLI PARDA: gorizontal=vaqt, vertikal=ovoz
var shield=document.getElementById('absolute-shield');

shield.addEventListener('pointerdown',function(e){
  if(!player)return;
  isSwiping=false;swipeDirection=null;
  startX=e.clientX;startY=e.clientY;
  startVideoTime=player.getCurrentTime();startVolume=player.getVolume();
  shield.setPointerCapture(e.pointerId);
});

shield.addEventListener('pointermove',function(e){
  if(e.buttons!==1&&e.pointerType==='mouse')return;
  if(!player||startX===0||startY===0)return;
  var dx=e.clientX-startX,dy=e.clientY-startY;
  if(!swipeDirection){
    if(Math.abs(dx)>15&&Math.abs(dx)>Math.abs(dy))swipeDirection='horizontal';
    else if(Math.abs(dy)>15&&Math.abs(dy)>Math.abs(dx))swipeDirection='vertical';
  }
  if(swipeDirection==='horizontal'){
    isSwiping=true;
    var seekOffset=(dx/(shield.clientWidth/2))*60;
    var newTime=Math.max(0,Math.min(player.getDuration(),startVideoTime+seekOffset));
    seekBar.value=newTime;
    document.getElementById('time-display').innerText=formatTime(newTime)+' / '+formatTime(player.getDuration());
    showIndicator((seekOffset>0?'>> ':'<< ')+formatTime(newTime));
  }else if(swipeDirection==='vertical'){
    isSwiping=true;
    var volOffset=-(dy/(shield.clientHeight/2))*100;
    var newVol=Math.max(0,Math.min(100,startVolume+volOffset));
    player.setVolume(newVol);
    if(newVol===0)player.mute();else player.unMute();
    showIndicator((newVol===0?'[X] ':'+  ')+Math.round(newVol)+'%');
  }
});

shield.addEventListener('pointerup',function(e){
  if(startX===0)return;
  startX=0;startY=0;
  if(isSwiping){
    if(swipeDirection==='horizontal')player.seekTo(seekBar.value,true);
    isSwiping=false;swipeDirection=null;
    hideIndicator();return;
  }
  var now=Date.now(),diff=now-lastClickTime;
  var rect=shield.getBoundingClientRect(),isRight=e.clientX>(rect.left+rect.width/2);
  if(diff<300&&diff>0){
    clearTimeout(clickTimer);
    var newT=player.getCurrentTime()+(isRight?10:-10);
    player.seekTo(Math.max(0,newT),true);
    showIndicator(isRight?'>> +10s':'<< -10s');
    setTimeout(hideIndicator,700);lastClickTime=0;
  }else{
    lastClickTime=now;
    clickTimer=setTimeout(function(){
      togglePlayPause();
      document.getElementById('settings-menu').style.display='none';
    },300);
  }
});

function showIndicator(text){
  var ind=document.getElementById('tap-indicator');
  ind.innerText=text;ind.style.opacity='1';
}
function hideIndicator(){document.getElementById('tap-indicator').style.opacity='0';}

function toggleSettings(){
  var m=document.getElementById('settings-menu');
  m.style.display=m.style.display==='block'?'none':'block';
}
function changeSpeed(r){if(player)player.setPlaybackRate(parseFloat(r));}
function populateQualities(){
  var q=document.getElementById('quality-select');
  if(!player||typeof player.getAvailableQualityLevels!=='function')return;
  var levels=player.getAvailableQualityLevels();
  if(levels&&levels.length>0){
    q.innerHTML='';
    var mp={highres:'4K',hd1440:'1440p',hd1080:'1080p',hd720:'720p',large:'480p',medium:'360p',small:'240p',tiny:'144p'};
    levels.forEach(function(l){var o=document.createElement('option');o.value=l;o.text=mp[l]||l;q.appendChild(o);});
  }
}
function changeQuality(q){if(player)player.setPlaybackQuality(q);}
</script>
</body></html>''';

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
      if (widget.type == 'pdf' && on && !_isPdfNative && !_isWeb) _tryDownload();
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

  // ─── WebViewController yaratish (autoplay ruxsati bilan) ─────
  WebViewController _newController() {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);
    // Android: media autoplay uchun user gesture talab qilinmasin
    if (ctrl.platform is AndroidWebViewController) {
      (ctrl.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    return ctrl;
  }

  // ─── VIDEO ────────────────────────────────────────────────────
  Future<void> _initVideo() async {
    if (_isWeb) { if (mounted) setState(() => _isLoading = false); return; }
    final url = ref.read(moduleDataProvider)?.videoUrl ?? '';
    if (url.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _error = 'Video manzili kiritilmagan'; });
      return;
    }

    final ctrl = _newController()
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted) setState(() => _isLoading = false); },
        // MUHIM: faqat asosiy frame xatosida error ko'rsatamiz
        // (YouTube API, reklama resurslari xatosi uchun EMAS)
        onWebResourceError: (err) {
          if ((err.isForMainFrame ?? false) && mounted) {
            setState(() { _isLoading = false; _error = 'Video yuklanmadi.'; });
          }
        },
      ));

    if (_isYt(url)) {
      final id = _ytId(url);
      if (id.isEmpty) {
        if (mounted) setState(() { _isLoading = false; _error = 'YouTube ID topilmadi'; });
        return;
      }
      // Custom player: loadHtmlString + baseUrl=youtube.com (IFrame API uchun)
      ctrl.loadHtmlString(_ytHtml(id), baseUrl: 'https://www.youtube.com');
    } else {
      // Drive video: /preview
      ctrl.loadRequest(Uri.parse(_previewUrl(url)));
    }
    if (mounted) setState(() => _videoWeb = ctrl);
  }

  // ─── PDF ──────────────────────────────────────────────────────
  Future<void> _initPdf() async {
    if (_isWeb) { if (mounted) setState(() => _isLoading = false); return; }
    final url = ref.read(moduleDataProvider)?.pdfUrl ?? '';
    if (url.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _error = 'PDF manzili kiritilmagan'; });
      return;
    }
    // 1. Cache → pdfx
    final cf = await _cacheFile(url);
    if (await cf.exists() && await cf.length() > 1024) {
      try {
        final c = PdfController(document: PdfDocument.openFile(cf.path));
        if (mounted) setState(() { _pdfCtrl = c; _isPdfNative = true; _isLoading = false; });
        if (_isOnline) _tryDownload();
        return;
      } catch (_) { await cf.delete(); }
    }
    // 2. WebView /preview (darhol)
    _initPdfWebView(url);
    if (_isOnline) _tryDownload();
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
      ..loadRequest(Uri.parse(_previewUrl(url)));
    if (mounted && !_isPdfNative) setState(() => _pdfWeb = c);
  }

  Future<void> _tryDownload() async {
    final url = ref.read(moduleDataProvider)?.pdfUrl ?? '';
    if (url.isEmpty) return;
    final file = await _cacheFile(url);
    final ok = await _downloadPdfFile(_downloadUrl(url), file);
    if (!ok || !mounted) return;
    try {
      final c = PdfController(document: PdfDocument.openFile(file.path));
      if (mounted) setState(() {
        _pdfCtrl?.dispose(); _pdfCtrl = c; _isPdfNative = true; _pdfWeb = null;
      });
    } catch (_) {}
  }

  // ─── FULLSCREEN & ROTATE ──────────────────────────────────────
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

  // ─── BUILD ────────────────────────────────────────────────────
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
                  color: AppColors.primary)),
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
            setState(() { _isLoading = true; _error = null; _isPdfNative = false; _pdfWeb = null; });
            widget.type == 'pdf' ? _initPdf() : _initVideo();
          },
          icon: const Icon(Icons.refresh), label: const Text('Qayta urinish'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent)),
      ])));
    }

    // ── VIDEO ──────────────────────────────────────────────────
    if (widget.type == 'video') {
      if (_isWeb) {
        final embed = _isYt(url)
            ? 'https://www.youtube.com/embed/${_ytId(url)}?rel=0&modestbranding=1&controls=1'
            : _previewUrl(url);
        return buildWebIframe(embed, true, key: ValueKey('vid_${data.artikul}'));
      }
      if (_videoWeb != null) return _buildVideoStack(url);
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    // ── PDF ────────────────────────────────────────────────────
    if (_isWeb) return buildWebIframe(url, false, key: ValueKey('pdf_${data.artikul}'));
    if (_isPdfNative && _pdfCtrl != null) {
      return PdfView(controller: _pdfCtrl!, scrollDirection: Axis.vertical,
          onDocumentLoaded: (d) { if (mounted) setState(() => _pdfTotal = d.pagesCount); },
          onPageChanged: (p) { if (mounted) setState(() => _pdfPage = p); });
    }
    if (_pdfWeb != null) return _buildPdfWebStack();
    return const Center(child: CircularProgressIndicator(color: AppColors.accent));
  }

  // ─── VIDEO STACK: o'ng-tepa + pastki pardalar ─────────────────
  Widget _buildVideoStack(String url) {
    final isDrive = _isDrive(url);
    return Stack(children: [
      WebViewWidget(controller: _videoWeb!),
      // O'ng-tepa: "Tashqarida ochish" / YouTube logo bloklash
      Positioned(top: 0, right: 0,
          child: PointerInterceptor(
              child: Container(width: 80, height: 80, color: Colors.transparent))),
      // Drive pastki bar
      if (isDrive)
        Positioned(bottom: 0, left: 0, right: 0,
            child: PointerInterceptor(
                child: Container(height: 50, color: Colors.transparent))),
      // YouTube pastki-chap logo
      if (!isDrive)
        Positioned(bottom: 0, left: 0,
            child: PointerInterceptor(
                child: Container(width: 180, height: 55, color: Colors.transparent))),
    ]);
  }

  // ─── PDF WebView STACK: o'ng-tepa "Open with" bloklash ────────
  Widget _buildPdfWebStack() {
    return Stack(children: [
      WebViewWidget(controller: _pdfWeb!),
      // O'ng-tepa burchak: Drive PDF "Open with" / "Pop-out" tugmasi
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