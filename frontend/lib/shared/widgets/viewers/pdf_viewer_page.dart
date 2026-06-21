import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:http/http.dart' as http;

import 'src/pdf_viewer_web_stub.dart'
    if (dart.library.html) 'src/pdf_viewer_web.dart';

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
    registerPdfViewFactory(url);
    return const SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: HtmlElementView(viewType: 'pdf-iframe-view'),
    );
  }

  Widget _buildMobilePdfViewer() {
    return SfPdfViewer.network(url);
  }
}
