import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

bool _isYoutubeEmbed(String url) => url.contains('youtube.com/embed');

Widget buildWebIframe(String url, bool isVideo, {Key? key}) {
  final String viewType = 'media-${url.hashCode}';

  try {
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      if (isVideo) {
        if (_isYoutubeEmbed(url)) {
          return _buildYoutubeWrapper(url);
        } else {
          return _buildVideoWrapper(url);
        }
      } else {
        return _buildPdfWrapper(url);
      }
    });
  } catch (e) {}

  return HtmlElementView(key: key, viewType: viewType);
}

// HTML5 video — Drive uchun (hech qanday tashqi tugma yo'q)
html.Element _buildVideoWrapper(String url) {
  final wrapper = html.DivElement()
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.background = '#000'
    ..style.display = 'flex'
    ..style.alignItems = 'center'
    ..style.justifyContent = 'center';

  final video = html.VideoElement()
    ..controls = true
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.objectFit = 'contain'
    ..setAttribute('controlsList', 'nodownload noremoteplayback')
    ..setAttribute('disablePictureInPicture', '')
    ..src = url;

  // O'ng klik menyusini bloklash
  video.onContextMenu.listen((e) => e.preventDefault());

  wrapper.append(video);
  return wrapper;
}

// PDF.js — Drive PDF uchun (Google Docs Viewer yo'q)
html.Element _buildPdfWrapper(String url) {
  final pdfJsHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { background:#525659; font-family:sans-serif; overflow-x:hidden; }
  #controls {
    background:#323639; padding:8px 12px;
    display:flex; align-items:center; justify-content:center;
    gap:8px; color:white; font-size:14px;
    position:sticky; top:0; z-index:10;
  }
  #controls button {
    background:#5f6368; color:white; border:none;
    padding:5px 12px; border-radius:4px; cursor:pointer; font-size:14px;
  }
  #controls button:hover { background:#80868b; }
  #controls button:disabled { opacity:0.4; cursor:default; }
  #canvas-container {
    padding:10px; display:flex;
    flex-direction:column; align-items:center; gap:8px;
  }
  canvas { max-width:100%; box-shadow:0 2px 8px rgba(0,0,0,0.4); background:white; }
  #status { color:#ccc; text-align:center; padding:40px; font-size:15px; }
</style>
</head>
<body>
<div id="controls">
  <button id="btn-prev" onclick="prevPage()" disabled>◀</button>
  <span id="page-info">Yuklanmoqda...</span>
  <button id="btn-next" onclick="nextPage()" disabled>▶</button>
  <button onclick="zoomOut()">−</button>
  <span id="zoom-info">100%</span>
  <button onclick="zoomIn()">+</button>
</div>
<div id="canvas-container">
  <div id="status">PDF yuklanmoqda...</div>
</div>

<script src="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js"></script>
<script>
  pdfjsLib.GlobalWorkerOptions.workerSrc =
    'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';

  var pdfDoc = null;
  var currentPage = 1;
  var totalPages = 0;
  var scale = 1.0;

  function getContainerWidth() {
    return document.getElementById('canvas-container').clientWidth - 20;
  }

  function renderPage(num) {
    pdfDoc.getPage(num).then(function(page) {
      var container = document.getElementById('canvas-container');
      container.innerHTML = '';

      var baseViewport = page.getViewport({scale: 1});
      var fitScale = getContainerWidth() / baseViewport.width;
      var viewport = page.getViewport({scale: fitScale * scale});

      var canvas = document.createElement('canvas');
      var ctx = canvas.getContext('2d');
      canvas.height = viewport.height;
      canvas.width = viewport.width;
      container.appendChild(canvas);

      page.render({canvasContext: ctx, viewport: viewport});
      document.getElementById('page-info').textContent = num + ' / ' + totalPages;
      document.getElementById('btn-prev').disabled = (num <= 1);
      document.getElementById('btn-next').disabled = (num >= totalPages);
    });
  }

  function prevPage() { if (currentPage > 1) { currentPage--; renderPage(currentPage); } }
  function nextPage() { if (currentPage < totalPages) { currentPage++; renderPage(currentPage); } }
  function zoomIn() {
    scale = Math.min(scale + 0.25, 3.0);
    document.getElementById('zoom-info').textContent = Math.round(scale * 100) + '%';
    renderPage(currentPage);
  }
  function zoomOut() {
    scale = Math.max(scale - 0.25, 0.5);
    document.getElementById('zoom-info').textContent = Math.round(scale * 100) + '%';
    renderPage(currentPage);
  }

  pdfjsLib.getDocument({url: '${url}', withCredentials: false}).promise
    .then(function(pdf) {
      pdfDoc = pdf;
      totalPages = pdf.numPages;
      document.getElementById('status').remove();
      renderPage(currentPage);
    })
    .catch(function(err) {
      document.getElementById('status').textContent =
        'PDF yuklanmadi. Iltimos qayta urinib koring.';
      console.error(err);
    });
</script>
</body>
</html>
''';

  final iframe = html.IFrameElement()
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    ..setAttribute('srcdoc', pdfJsHtml);

  return iframe;
}

// YouTube iframe — shieldlar bilan
html.Element _buildYoutubeWrapper(String url) {
  final wrapper = html.DivElement()
    ..style.position = 'relative'
    ..style.width = '100%'
    ..style.height = '100%';

  final iframe = html.IFrameElement()
    ..src = url
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    ..allowFullscreen = true;

  final topLeftShield = html.DivElement()
    ..style.position = 'absolute'
    ..style.top = '0'
    ..style.left = '60px'
    ..style.height = '60px'
    ..style.width = '60%'
    ..style.zIndex = '999';

  final bottomLeftShield = html.DivElement()
    ..style.position = 'absolute'
    ..style.bottom = '0'
    ..style.left = '0'
    ..style.width = '160px'
    ..style.height = '75px'
    ..style.zIndex = '999';

  final bottomRightShield = html.DivElement()
    ..style.position = 'absolute'
    ..style.bottom = '0'
    ..style.right = '0'
    ..style.width = '100px'
    ..style.height = '50px'
    ..style.zIndex = '999';

  wrapper.children.addAll([iframe, topLeftShield, bottomLeftShield, bottomRightShield]);
  return wrapper;
}

void setWebZoomable(bool isZoomable) {
  try {
    final meta = html.document.querySelector('meta[name="viewport"]');
    if (meta != null) {
      meta.setAttribute('content', isZoomable
          ? 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes'
          : 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover');
    }
  } catch (e) {}
}