import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

bool _isYoutubeEmbed(String url) => url.contains('youtube.com/embed');
bool _isDrivePreview(String url) => url.contains('drive.google.com');

Widget buildWebIframe(String url, bool isVideo, {Key? key}) {
  final String viewType = 'media-${url.hashCode}';

  try {
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      if (isVideo) {
        if (_isYoutubeEmbed(url)) {
          return _buildYoutubeWrapper(url);
        } else {
          // Drive video: iframe /preview (HTML5 <video> CORS bloklanadi)
          return _buildDriveIframeWrapper(url);
        }
      } else {
        return _buildPdfWrapper(url);
      }
    });
  } catch (e) {}

  return HtmlElementView(key: key, viewType: viewType);
}

// Drive video — iframe /preview
html.Element _buildDriveIframeWrapper(String url) {
  final wrapper = html.DivElement()
    ..style.position = 'relative'
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.background = '#000';

  final iframe = html.IFrameElement()
    ..src = url
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    ..allowFullscreen = true;

  // Top-right "Pop-out" tugmasini bloklash (Pagination va Zoom uchun pastki qism ochiq qoldi)
  final topRightShield = html.DivElement()
    ..style.position = 'absolute'
    ..style.top = '0'
    ..style.right = '0'
    ..style.width = '80px'
    ..style.height = '80px'
    ..style.zIndex = '999';

  wrapper.children.addAll([iframe, topRightShield]);
  return wrapper;
}

// PDF.js — Drive PDF uchun (Google Docs Viewer yo'q)
html.Element _buildPdfWrapper(String url) {
  final id = RegExp(r'[-\w]{25,}').firstMatch(url)?.group(0);
  final previewUrl = id != null
      ? 'https://drive.google.com/file/d/$id/preview'
      : url;

  final wrapper = html.DivElement()
    ..style.position = 'relative'
    ..style.width = '100%'
    ..style.height = '100%';

  final iframe = html.IFrameElement()
    ..src = previewUrl
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    ..allowFullscreen = true;

  // PDF Pop-out tugmasini to'sish (Zoom va Pagination ishlashi uchun pastki qism ochiq)
  final topRightShield = html.DivElement()
    ..style.position = 'absolute'
    ..style.top = '0'
    ..style.right = '0'
    ..style.width = '80px'
    ..style.height = '80px'
    ..style.zIndex = '999';

  wrapper.children.addAll([iframe, topRightShield]);
  return wrapper;
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