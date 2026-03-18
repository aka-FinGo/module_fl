import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

bool _isYoutubeEmbed(String url) => url.contains('youtube.com/embed');

// isDirectVideo = true → <video> tag (Telegram URL uchun)
// isDirectVideo = false → iframe (YouTube, Drive, Google Docs Viewer)
Widget buildWebIframe(String url, bool isVideo, {
  Key? key,
  bool isDirectVideo = false,
}) {
  final String viewType = 'media-${url.hashCode}-${isDirectVideo ? 'v' : 'i'}';

  try {
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      if (isVideo) {
        if (isDirectVideo) {
          // Telegram to'g'ridan URL → <video> tag
          return _buildVideoTag(url);
        } else if (_isYoutubeEmbed(url)) {
          return _buildYoutubeWrapper(url);
        } else {
          return _buildIframeWrapper(url, background: '#000');
        }
      } else {
        // PDF — Google Docs Viewer yoki Drive /preview → iframe
        return _buildIframeWrapper(url, background: '#525659');
      }
    });
  } catch (e) {
    // Allaqachon ro'yxatdan o'tgan — davom etamiz
  }

  return HtmlElementView(key: key, viewType: viewType);
}

// ── <video> tag (Telegram to'g'ridan URL) ────────────────────
html.Element _buildVideoTag(String url) {
  final wrapper = html.DivElement()
    ..style.position = 'relative'
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.background = '#000'
    ..style.display = 'flex'
    ..style.alignItems = 'center'
    ..style.justifyContent = 'center';

  final video = html.VideoElement()
    ..src = url
    ..controls = true
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.maxHeight = '100%'
    ..style.background = '#000'
    ..setAttribute('playsinline', 'true')
    ..setAttribute('controlsList', 'nodownload');

  wrapper.children.add(video);
  return wrapper;
}

// ── Universal iframe wrapper ──────────────────────────────────
html.Element _buildIframeWrapper(String url, {String background = '#fff'}) {
  final wrapper = html.DivElement()
    ..style.position = 'relative'
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.background = background;

  final iframe = html.IFrameElement()
    ..src = url
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    ..allowFullscreen = true;

  // Top-right "Pop-out" tugmasini bloklash
  final shield = html.DivElement()
    ..style.position = 'absolute'
    ..style.top = '0'
    ..style.right = '0'
    ..style.width = '80px'
    ..style.height = '80px'
    ..style.zIndex = '999';

  wrapper.children.addAll([iframe, shield]);
  return wrapper;
}

// ── YouTube iframe + shieldlar ────────────────────────────────
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

  final topShield = html.DivElement()
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

  wrapper.children.addAll([iframe, topShield, bottomLeftShield, bottomRightShield]);
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
