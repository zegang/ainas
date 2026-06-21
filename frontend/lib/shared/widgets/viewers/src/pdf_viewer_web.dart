import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

void registerPdfViewFactory(String url) {
  ui_web.platformViewRegistry.registerViewFactory(
    'pdf-iframe-view',
    (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true;
      iframe.setAttribute('allow', 'fullscreen');
      return iframe;
    },
  );
}
