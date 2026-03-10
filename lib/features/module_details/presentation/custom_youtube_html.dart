/// YouTube IFrame API bilan to'liq custom player HTML generatori.
/// Swipe (gorizontal=vaqt, vertikal=ovoz), custom controls,
/// tezlik va sifat sozlamalari, double-tap ±10s.
String buildCustomYoutubeHtml(String videoId) {
  return '''<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
html,body{width:100%;height:100%;background:#000;overflow:hidden}
#wrap{position:relative;width:100%;height:100%;user-select:none}
#yt{width:100%;height:100%;pointer-events:none;border:none;display:block}
#shield{position:absolute;top:0;left:0;width:100%;height:calc(100% - 52px);z-index:10;background:transparent;touch-action:none}
#ind{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);background:rgba(0,0,0,.75);color:#fff;padding:10px 20px;border-radius:10px;font:bold 20px sans-serif;opacity:0;transition:opacity .15s;z-index:20;pointer-events:none;text-align:center;white-space:nowrap}
#loader{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);width:38px;height:38px;border:3px solid rgba(255,255,255,.2);border-top-color:#27ae60;border-radius:50%;animation:spin .8s linear infinite;z-index:5}
@keyframes spin{to{transform:translate(-50%,-50%) rotate(360deg)}}
#bar{position:absolute;bottom:0;left:0;right:0;height:52px;background:rgba(12,12,12,.97);display:flex;align-items:center;padding:0 8px;gap:6px;z-index:30}
.cb{background:none;border:none;color:#fff;font-size:17px;cursor:pointer;padding:5px 6px;outline:none;flex-shrink:0}
.cb:active{color:#27ae60}
#seek{flex:1;cursor:pointer;accent-color:#27ae60;height:4px}
#time{color:#ccc;font-size:11px;font-weight:bold;min-width:90px;text-align:center;font-variant-numeric:tabular-nums;flex-shrink:0}
#menu{position:absolute;bottom:58px;right:8px;background:rgba(12,12,12,.97);color:#fff;padding:12px;border-radius:8px;z-index:40;display:none;min-width:155px;box-shadow:0 4px 12px rgba(0,0,0,.7)}
.sr{display:flex;justify-content:space-between;align-items:center;margin-bottom:11px}
.sr:last-child{margin-bottom:0}
.sr label{font-size:12px}
.sr select{background:#333;color:#fff;border:1px solid #555;border-radius:4px;padding:3px 5px;outline:none;font-size:11px}
</style>
</head>
<body>
<div id="wrap">
  <div id="loader"></div>
  <div id="yt"></div>
  <div id="shield"></div>
  <div id="ind"></div>
  <div id="menu">
    <div class="sr"><label>Tezlik</label>
      <select id="spd" onchange="setSp(this.value)">
        <option value=".5">.5x</option><option value=".75">.75x</option>
        <option value="1" selected>Normal</option><option value="1.25">1.25x</option>
        <option value="1.5">1.5x</option><option value="2">2x</option>
      </select></div>
    <div class="sr"><label>Sifat</label>
      <select id="ql" onchange="setQl(this.value)"><option value="default">Avto</option></select></div>
  </div>
  <div id="bar">
    <button class="cb" id="ppb" onclick="togPlay()">&#9654;</button>
    <input type="range" id="seek" value="0" step=".1" oninput="onSi()" onchange="onSc()">
    <span id="time">0:00 / 0:00</span>
    <button class="cb" onclick="togMenu()">&#9881;</button>
  </div>
</div>
<script>
var s=document.createElement('script');
s.src='https://www.youtube.com/iframe_api';
document.head.appendChild(s);
var P,tick,drag=false;
function onYouTubeIframeAPIReady(){
  P=new YT.Player('yt',{videoId:'$videoId',height:'100%',width:'100%',
    playerVars:{controls:0,disablekb:1,rel:0,modestbranding:1,playsinline:1,iv_load_policy:3,fs:0,autoplay:1},
    events:{
      onReady:function(e){document.getElementById('loader').style.display='none';e.target.playVideo();startTick();fillQl();},
      onStateChange:function(e){document.getElementById('ppb').innerHTML=e.data===1?'&#9646;&#9646;':'&#9654;';e.data===1?startTick():stopTick();}
    }});
}
function fmt(s){s=Math.max(0,Math.floor(s));return Math.floor(s/60)+':'+(s%60<10?'0':'')+s%60}
function startTick(){clearInterval(tick);tick=setInterval(function(){
  if(!P||drag||sw)return;
  var c=P.getCurrentTime()||0,t=P.getDuration()||0;
  document.getElementById('time').textContent=fmt(c)+' / '+fmt(t);
  if(t>0){var k=document.getElementById('seek');k.max=t;k.value=c;}
},400);}
function stopTick(){clearInterval(tick);}
function togPlay(){if(!P)return;P.getPlayerState()===1?P.pauseVideo():P.playVideo();hideMn();}
function onSi(){drag=true;var k=document.getElementById('seek');document.getElementById('time').textContent=fmt(k.value)+' / '+fmt(P?P.getDuration():0);}
function onSc(){if(P)P.seekTo(document.getElementById('seek').value,true);drag=false;}
function togMenu(){var m=document.getElementById('menu');m.style.display=m.style.display==='block'?'none':'block';}
function hideMn(){document.getElementById('menu').style.display='none';}
function setSp(v){if(P)P.setPlaybackRate(parseFloat(v));}
function fillQl(){
  if(!P||!P.getAvailableQualityLevels)return;
  var lv=P.getAvailableQualityLevels();if(!lv||!lv.length)return;
  var mp={highres:'4K',hd1440:'1440p',hd1080:'1080p',hd720:'720p',large:'480p',medium:'360p',small:'240p',tiny:'144p'};
  var q=document.getElementById('ql');q.innerHTML='<option value="default">Avto</option>';
  lv.forEach(function(l){var o=document.createElement('option');o.value=l;o.text=mp[l]||l;q.appendChild(o);});}
function setQl(v){if(P)P.setPlaybackQuality(v);}
var sw=false,dir=null,sx=0,sy=0,st=0,sv=0,lt=0,tt=null;
var sh=document.getElementById('shield');
sh.addEventListener('pointerdown',function(e){
  if(!P)return;sh.setPointerCapture(e.pointerId);
  sw=false;dir=null;sx=e.clientX;sy=e.clientY;st=P.getCurrentTime();sv=P.getVolume();hideMn();
});
sh.addEventListener('pointermove',function(e){
  if(!P||sx===0)return;
  if(e.buttons===0&&e.pointerType==='mouse')return;
  var dx=e.clientX-sx,dy=e.clientY-sy;
  if(!dir){
    if(Math.abs(dx)>12&&Math.abs(dx)>Math.abs(dy))dir='h';
    else if(Math.abs(dy)>12&&Math.abs(dy)>Math.abs(dx))dir='v';
  }
  if(dir==='h'){sw=true;
    var nt=Math.max(0,Math.min(P.getDuration(),st+(dx/(sh.clientWidth*.5))*60));
    document.getElementById('seek').value=nt;
    document.getElementById('time').textContent=fmt(nt)+' / '+fmt(P.getDuration());
    showI(dx>0?'\u23E9 '+fmt(nt):'\u23EA '+fmt(nt));
  }else if(dir==='v'){sw=true;
    var nv=Math.max(0,Math.min(100,sv-(dy/(sh.clientHeight*.5))*100));
    P.setVolume(nv);nv===0?P.mute():P.unMute();
    showI(nv===0?'\uD83D\uDD07 ':'\uD83D\uDD0A '+Math.round(nv)+'%');
  }
});
sh.addEventListener('pointerup',function(e){
  if(sx===0)return;
  var was=sw,d=dir;sx=0;sy=0;sw=false;dir=null;
  if(was){if(d==='h')P.seekTo(document.getElementById('seek').value,true);hideI();return;}
  var now=Date.now(),rect=sh.getBoundingClientRect(),right=e.clientX>rect.left+rect.width/2;
  if(now-lt<300&&now-lt>0){
    clearTimeout(tt);P.seekTo(Math.max(0,P.getCurrentTime()+(right?10:-10)),true);
    showI(right?'\u23E9 +10s':'\u23EA -10s');setTimeout(hideI,700);lt=0;
  }else{lt=now;tt=setTimeout(togPlay,280);}
});
function showI(t){var e=document.getElementById('ind');e.textContent=t;e.style.opacity='1';}
function hideI(){document.getElementById('ind').style.opacity='0';}
</script>
</body>
</html>''';
}

/// YouTube URL dan video ID ajratib olish
String extractYoutubeId(String url) {
  if (url.contains('youtu.be/')) return url.split('youtu.be/')[1].split('?')[0];
  if (url.contains('youtube.com/watch')) return Uri.parse(url).queryParameters['v'] ?? '';
  if (url.contains('youtube.com/embed/')) return url.split('youtube.com/embed/')[1].split('?')[0];
  return '';
}