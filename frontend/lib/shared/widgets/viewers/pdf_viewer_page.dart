import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:http/http.dart' as http;

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
      appBar: AppBar(
        title: Text(title),
      ),
      body: kIsWeb
          ? FutureBuilder<http.Response>(
              future: http.get(Uri.parse(url)),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Failed to load PDF: ${snapshot.error}'));
                }
                final response = snapshot.data;
                if (response == null || response.statusCode != 200) {
                  return Center(child: Text('Failed to load PDF: ${response?.statusCode ?? 'unknown'}'));
                }
                return SfPdfViewer.memory(response.bodyBytes);
              },
            )
          : SfPdfViewer.network(url),
    );
  }
}