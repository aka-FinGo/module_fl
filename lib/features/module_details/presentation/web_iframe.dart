import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

Widget buildWebIframe(String url, {Key? key}) {
  final String viewType = 'iframe-view-${url.hashCode}';

  // Registratsiya faqat bir marta bo'lganiga ishonch qilish (yoki xatoni bypass qilish)
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

      // Yuqorisidagi sarlavha, share tugmalarini yopuvchi parda (pointer-events: auto -> o'ziga oladi)
      final html.DivElement topShield = html.DivElement()
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0'
        ..style.right = '0'
        ..style.height = '60px'
        ..style.backgroundColor = 'transparent'
        ..style.zIndex = '999';

      // Pastki YouTube va boshqa control tugmalarini qisman parda qilish
      final html.DivElement bottomShield = html.DivElement()
        ..style.position = 'absolute'
        ..style.bottom = '0'
        ..style.right = '0'
        ..style.width = '100px'
        ..style.height = '60px'
        ..style.backgroundColor = 'transparent'
        ..style.zIndex = '999';

      wrapper.children.addAll([iframe, topShield, bottomShield]);
      return wrapper;
    });
  } catch (e) {
    // Already registered xatosi e'tiborsiz qoldiriladi
  }

  return HtmlElementView(
    key: key,
    viewType: viewType,
  );
}
