import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

Widget buildWebIframe(String url, bool isVideo, {Key? key}) {
  final String viewType = 'iframe-view-${url.hashCode}';

  try {
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final html.DivElement wrapper = html.DivElement()
        ..style.position = 'relative'
        ..style.width = '100%'
        ..style.height = '100%';

      final html.IFrameElement iframe = html.IFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.height = '100%'
        ..style.width = '100%'
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0'
        ..allowFullscreen = true;

      if (isVideo) {
        // Top-left: Block video title and channel link (approx 70% width)
        final html.DivElement topLeftShield = html.DivElement()
          ..style.position = 'absolute'
          ..style.top = '0'
          ..style.left = '0'
          ..style.height = '60px'
          ..style.width = '70%'
          ..style.backgroundColor = 'transparent'
          ..style.zIndex = '999';

        // Bottom-left: Block Share and Watch Later buttons
        final html.DivElement bottomLeftShield = html.DivElement()
          ..style.position = 'absolute'
          ..style.bottom = '0'
          ..style.left = '0'
          ..style.width = '120px'
          ..style.height = '70px' // Increased height to cover share
          ..style.backgroundColor = 'transparent'
          ..style.zIndex = '999';

        // Bottom-right: Block YouTube logo
        final html.DivElement bottomRightShield = html.DivElement()
          ..style.position = 'absolute'
          ..style.bottom = '0'
          ..style.right = '0'
          ..style.width = '100px'
          ..style.height = '60px'
          ..style.backgroundColor = 'transparent'
          ..style.zIndex = '999';

        wrapper.children.addAll(
            [iframe, topLeftShield, bottomLeftShield, bottomRightShield]);
      } else {
        // PDF: Only block top-right pop-out button
        final html.DivElement topRightShield = html.DivElement()
          ..style.position = 'absolute'
          ..style.top = '0'
          ..style.right = '0'
          ..style.width = '80px' // Slightly wider to be sure
          ..style.height = '60px'
          ..style.backgroundColor = 'transparent'
          ..style.zIndex = '999';

        wrapper.children.addAll([iframe, topRightShield]);
      }

      return wrapper;
    });
  } catch (e) {
    // Already registered is fine
  }

  return HtmlElementView(
    key: key,
    viewType: viewType,
  );
}

void setWebZoomable(bool isZoomable) {
  try {
    final meta = html.document.querySelector('meta[name="viewport"]');
    if (meta != null) {
      if (isZoomable) {
        meta.setAttribute('content',
            'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes');
      } else {
        meta.setAttribute('content',
            'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover');
      }
    }
  } catch (e) {
    // Ignore
  }
}
