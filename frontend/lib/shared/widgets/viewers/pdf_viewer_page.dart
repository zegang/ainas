import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;

String? _currentPdfUrl;

void registerPdfViewFactory() {
  if (kIsWeb) {
    ui_web.platformViewRegistry.registerViewFactory(
      'pdf-iframe-view',
      (int viewId) {
        final iframe = web.HTMLIFrameElement()
          ..src = _currentPdfUrl ?? ''
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true;
        iframe.setAttribute('allow', 'fullscreen');
        return iframe;
      },
    );
  }
}

class PdfViewerPage extends StatelessWidget {
  final String url;
  final String title;

  const PdfViewerPage({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final _log = Logger('PdfViewerPage');
    _log.info('Loading PDF from URL: $url');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: kIsWeb ? _buildWebPdfViewer() : _buildMobilePdfViewer(),
    );
  }

  Widget _buildWebPdfViewer() {
    registerPdfViewFactory();
    _currentPdfUrl = url;
    
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: HtmlElementView(viewType: 'pdf-iframe-view'),
    );
  }

  Widget _buildMobilePdfViewer() {
    return SfPdfViewer.network(url);
  }
}
