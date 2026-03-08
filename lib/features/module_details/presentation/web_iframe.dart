import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

Widget buildWebIframe(String url, {Key? key}) {
  final String viewType = 'iframe-view-${url.hashCode}';

  // Registratsiya faqat bir marta bo'lganiga ishonch qilish (yoki xatoni bypass qilish)
  try {
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final html.IFrameElement iframe = html.IFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.height = '100%'
        ..style.width = '100%'
        ..allowFullscreen = true;
      return iframe;
    });
  } catch (e) {
    // Already registered xatosi e'tiborsiz qoldiriladi
  }

  return HtmlElementView(
    key: key,
    viewType: viewType,
  );
}
