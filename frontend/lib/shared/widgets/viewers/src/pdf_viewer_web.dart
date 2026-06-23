import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

web.HTMLIFrameElement? _pdfIframe;

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
      _pdfIframe = iframe;
      return iframe;
    },
  );
}

void setPdfPointerEvents(bool enabled) {
  if (_pdfIframe != null) {
    _pdfIframe!.style.pointerEvents = enabled ? 'auto' : 'none';
  }
}
