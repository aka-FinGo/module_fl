import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget buildWebIframe(String url, bool isVideo, {
  Key? key,
  bool isDirectVideo = false,
}) {
  return Stack(
    key: key,
    children: [
      _MobileWebView(url: url),
      Positioned(
        top: 0, right: 0,
        child: Container(width: 80, height: 80, color: Colors.transparent),
      ),
    ],
  );
}

class _MobileWebView extends StatefulWidget {
  final String url;
  const _MobileWebView({required this.url, super.key});

  @override
  State<_MobileWebView> createState() => _MobileWebViewState();
}

class _MobileWebViewState extends State<_MobileWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

void setWebZoomable(bool isZoomable) {}
