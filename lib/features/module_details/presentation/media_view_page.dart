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

// ═══════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════

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

/// Drive virus-scan bypass bilan PDF yuklab olish
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

/// YouTube custom player HTML (IFrame API + swipe + controls)
String _ytHtml(String videoId) => '''<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
html,body{width:100%;height:100%;background:#000;overflow:hidden}
#w{position:relative;width:100%;height:100%;user-select:none}
#yt{width:100%;height:100%;pointer-events:none;border:none;display:block}
#sh{position:absolute;top:0;left:0;width:100%;height:calc(100% - 52px);z-index:10;background:transparent;touch-action:none}
#ind{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);background:rgba(0,0,0,.75);color:#fff;padding:10px 20px;border-radius:10px;font:bold 20px sans-serif;opacity:0;transition:opacity .15s;z-index:20;pointer-events:none;text-align:center;white-space:nowrap}
#ldr{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);width:38px;height:38px;border:3px solid rgba(255,255,255,.2);border-top-color:#27ae60;border-radius:50%;animation:sp .8s linear infinite;z-index:5}
@keyframes sp{to{transform:translate(-50%,-50%) rotate(360deg)}}
#bar{position:absolute;bottom:0;left:0;right:0;height:52px;background:rgba(12,12,12,.97);display:flex;align-items:center;padding:0 8px;gap:6px;z-index:30}
.cb{background:none;border:none;color:#fff;font-size:17px;cursor:pointer;padding:5px 6px;outline:none;flex-shrink:0}.cb:active{color:#27ae60}
#sk{flex:1;cursor:pointer;accent-color:#27ae60;height:4px}
#tm{color:#ccc;font-size:11px;font-weight:bold;min-width:90px;text-align:center;font-variant-numeric:tabular-nums;flex-shrink:0}
#mn{position:absolute;bottom:58px;right:8px;background:rgba(12,12,12,.97);color:#fff;padding:12px;border-radius:8px;z-index:40;display:none;min-width:155px;box-shadow:0 4px 12px rgba(0,0,0,.7)}
.sr{display:flex;justify-content:space-between;align-items:center;margin-bottom:11px}.sr:last-child{margin-bottom:0}
.sr label{font-size:12px}.sr select{background:#333;color:#fff;border:1px solid #555;border-radius:4px;padding:3px 5px;outline:none;font-size:11px}
</style></head><body>
<div id="w">
  <div id="ldr"></div><div id="yt"></div><div id="sh"></div><div id="ind"></div>
  <div id="mn">
    <div class="sr"><label>Tezlik</label>
      <select id="spd" onchange="setSp(this.value)">
        <option value=".5">.5x</option><option value=".75">.75x</option>
        <option value="1" selected>Normal</option><option value="1.25">1.25x</option>
        <option value="1.5">1.5x</option><option value="2">2x</option></select></div>
    <div class="sr"><label>Sifat</label>
      <select id="ql" onchange="setQl(this.value)"><option value="default">Avto</option></select></div>
  </div>
  <div id="bar">
    <button class="cb" id="ppb" onclick="togPlay()">&#9654;</button>
    <input type="range" id="sk" value="0" step=".1" oninput="onSi()" onchange="onSc()">
    <span id="tm">0:00 / 0:00</span>
    <button class="cb" onclick="togMn()">&#9881;</button>
  </div>
</div>
<script>
var s=document.createElement('script');s.src='https://www.youtube.com/iframe_api';document.head.appendChild(s);
var P,tk,dr=false;
function onYouTubeIframeAPIReady(){
  P=new YT.Player('yt',{videoId:'$videoId',height:'100%',width:'100%',
    playerVars:{controls:0,disablekb:1,rel:0,modestbranding:1,playsinline:1,iv_load_policy:3,fs:0,autoplay:1},
    events:{
      onReady:function(e){document.getElementById('ldr').style.display='none';e.target.playVideo();stTk();fillQl();},
      onStateChange:function(e){document.getElementById('ppb').innerHTML=e.data===1?'&#9646;&#9646;':'&#9654;';e.data===1?stTk():clTk();}
    }});}
function fmt(s){s=Math.max(0,Math.floor(s));return Math.floor(s/60)+':'+(s%60<10?'0':'')+s%60}
function stTk(){clearInterval(tk);tk=setInterval(function(){
  if(!P||dr||sw)return;var c=P.getCurrentTime()||0,t=P.getDuration()||0;
  document.getElementById('tm').textContent=fmt(c)+' / '+fmt(t);
  if(t>0){var k=document.getElementById('sk');k.max=t;k.value=c;}},400);}
function clTk(){clearInterval(tk);}
function togPlay(){if(!P)return;P.getPlayerState()===1?P.pauseVideo():P.playVideo();hidMn();}
function onSi(){dr=true;var k=document.getElementById('sk');document.getElementById('tm').textContent=fmt(k.value)+' / '+fmt(P?P.getDuration():0);}
function onSc(){if(P)P.seekTo(document.getElementById('sk').value,true);dr=false;}
function togMn(){var m=document.getElementById('mn');m.style.display=m.style.display==='block'?'none':'block';}
function hidMn(){document.getElementById('mn').style.display='none';}
function setSp(v){if(P)P.setPlaybackRate(parseFloat(v));}
function fillQl(){if(!P||!P.getAvailableQualityLevels)return;
  var lv=P.getAvailableQualityLevels();if(!lv||!lv.length)return;
  var mp={highres:'4K',hd1440:'1440p',hd1080:'1080p',hd720:'720p',large:'480p',medium:'360p',small:'240p',tiny:'144p'};
  var q=document.getElementById('ql');q.innerHTML='<option value="default">Avto</option>';
  lv.forEach(function(l){var o=document.createElement('option');o.value=l;o.text=mp[l]||l;q.appendChild(o);});}
function setQl(v){if(P)P.setPlaybackQuality(v);}
var sw=false,dir=null,sx=0,sy=0,st=0,sv=0,lt=0,tt=null;
var sh=document.getElementById('sh');
sh.addEventListener('pointerdown',function(e){
  if(!P)return;sh.setPointerCapture(e.pointerId);sw=false;dir=null;
  sx=e.clientX;sy=e.clientY;st=P.getCurrentTime();sv=P.getVolume();hidMn();});
sh.addEventListener('pointermove',function(e){
  if(!P||sx===0)return;if(e.buttons===0&&e.pointerType==='mouse')return;
  var dx=e.clientX-sx,dy=e.clientY-sy;
  if(!dir){if(Math.abs(dx)>12&&Math.abs(dx)>Math.abs(dy))dir='h';
    else if(Math.abs(dy)>12&&Math.abs(dy)>Math.abs(dx))dir='v';}
  if(dir==='h'){sw=true;
    var nt=Math.max(0,Math.min(P.getDuration(),st+(dx/(sh.clientWidth*.5))*60));
    document.getElementById('sk').value=nt;
    document.getElementById('tm').textContent=fmt(nt)+' / '+fmt(P.getDuration());
    showI(dx>0?'\u23E9 '+fmt(nt):'\u23EA '+fmt(nt));
  }else if(dir==='v'){sw=true;
    var nv=Math.max(0,Math.min(100,sv-(dy/(sh.clientHeight*.5))*100));
    P.setVolume(nv);nv===0?P.mute():P.unMute();
    showI(nv===0?'\uD83D\uDD07 ':'\uD83D\uDD0A '+Math.round(nv)+'%');}});
sh.addEventListener('pointerup',function(e){
  if(sx===0)return;var was=sw,d=dir;sx=0;sy=0;sw=false;dir=null;
  if(was){if(d==='h')P.seekTo(document.getElementById('sk').value,true);hideI();return;}
  var now=Date.now(),rect=sh.getBoundingClientRect(),right=e.clientX>rect.left+rect.width/2;
  if(now-lt<300&&now-lt>0){clearTimeout(tt);P.seekTo(Math.max(0,P.getCurrentTime()+(right?10:-10)),true);
    showI(right?'\u23E9 +10s':'\u23EA -10s');setTimeout(hideI,700);lt=0;
  }else{lt=now;tt=setTimeout(togPlay,280);}});
function showI(t){var e=document.getElementById('ind');e.textContent=t;e.style.opacity='1';}
function hideI(){document.getElementById('ind').style.opacity='0';}
</script></body></html>''';

// ═══════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════════════════════

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

  // ─── VIDEO ─────────────────────────────────────────────────────
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
      final id = _ytId(url);
      if (id.isEmpty) {
        if (mounted) setState(() { _isLoading = false; _error = 'YouTube ID topilmadi'; });
        return;
      }
      ctrl.loadHtmlString(_ytHtml(id), baseUrl: 'https://www.youtube.com');
    } else {
      ctrl.loadRequest(Uri.parse(_previewUrl(url)));
    }
    if (mounted) setState(() => _videoWeb = ctrl);
  }

  // ─── PDF ───────────────────────────────────────────────────────
  Future<void> _initPdf() async {
    if (_isWeb) { if (mounted) setState(() => _isLoading = false); return; }
    final url = ref.read(moduleDataProvider)?.pdfUrl ?? '';
    if (url.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _error = 'PDF manzili kiritilmagan'; });
      return;
    }
    // 1. Cache → pdfx (darhol)
    final cf = await _cacheFile(url);
    if (await cf.exists() && await cf.length() > 1024) {
      try {
        final c = PdfController(document: PdfDocument.openFile(cf.path));
        if (mounted) setState(() { _pdfCtrl = c; _isPdfNative = true; _isLoading = false; });
        if (_isOnline) _tryDownload();
        return;
      } catch (_) { await cf.delete(); }
    }
    // 2. Cache yo'q → WebView /preview (darhol ko'rinadi)
    _initPdfWebView(url);
    // 3. Fonda yuklab olish
    if (_isOnline) _tryDownload();
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
      if (mounted) setState(() { _pdfCtrl?.dispose(); _pdfCtrl = c; _isPdfNative = true; _pdfWeb = null; });
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
        final embedUrl = _isYt(url)
            ? 'https://www.youtube.com/embed/${_ytId(url)}?autoplay=0&rel=0&modestbranding=1&controls=1'
            : _previewUrl(url);
        return buildWebIframe(embedUrl, true, key: ValueKey('vid_${data.artikul}'));
      }
      if (_videoWeb != null) return _buildVideoStack(url);
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    // ── PDF ────────────────────────────────────────────────────
    // Web: Drive /preview iframe (GitHub Pages)
    if (_isWeb) return buildWebIframe(url, false, key: ValueKey('pdf_${data.artikul}'));
    // Mobile: pdfx (cache)
    if (_isPdfNative && _pdfCtrl != null) {
      return PdfView(
          controller: _pdfCtrl!, scrollDirection: Axis.vertical,
          onDocumentLoaded: (d) { if (mounted) setState(() => _pdfTotal = d.pagesCount); },
          onPageChanged: (p) { if (mounted) setState(() => _pdfPage = p); });
    }
    // Mobile: WebView /preview — o'ng-tepa parda bilan
    if (_pdfWeb != null) return _buildPdfWebStack();
    return const Center(child: CircularProgressIndicator(color: AppColors.accent));
  }

  /// Drive/YouTube video steki — o'ng-tepa + pastki pardalar
  Widget _buildVideoStack(String url) {
    final isDrive = _isDrive(url);
    return Stack(children: [
      WebViewWidget(controller: _videoWeb!),
      Positioned(top: 0, right: 0,
          child: PointerInterceptor(
              child: Container(width: 70, height: 70, color: Colors.transparent))),
      if (isDrive)
        Positioned(bottom: 0, left: 0, right: 0,
            child: PointerInterceptor(
                child: Container(height: 44, color: Colors.transparent))),
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
}