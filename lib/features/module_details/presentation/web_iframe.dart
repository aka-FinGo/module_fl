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

      wrapper.children.add(iframe);
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
