import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';
import 'package:ainas_frontend/shared/widgets/file_action_menu.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/features/ai_assistant/presentation/widgets/nas_dir_picker.dart';

import 'src/pdf_viewer_web_stub.dart'
    if (dart.library.html) 'src/pdf_viewer_web.dart';

class PdfViewerPage extends StatefulWidget {
  final String url;
  final String title;
  final FileItem? fileItem;
  final void Function(String action, FileItem item)? onActionSelected;

  const PdfViewerPage({
    super.key,
    required this.url,
    required this.title,
    this.fileItem,
    this.onActionSelected,
  });

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  final _api = ApiService();
  final _log = Logger('PdfViewerPage');
  final PdfViewerController _pdfController = PdfViewerController();
  double _currentZoom = 1.0;
  int _currentPage = 0;
  int _totalPages = 0;

  @override
  Widget build(BuildContext context) {
    _log.info('Loading PDF from URL: ${widget.url}');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: kIsWeb
            ? null
            : [
                if (_totalPages > 0) ...[
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous page',
                    onPressed: _currentPage > 1 ? () => _jumpToPage(_currentPage - 1) : null,
                  ),
                  GestureDetector(
                    onTap: _gotoPageDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade500),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$_currentPage / $_totalPages',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next page',
                    onPressed: _currentPage < _totalPages ? () => _jumpToPage(_currentPage + 1) : null,
                  ),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  icon: const Icon(Icons.zoom_out),
                  tooltip: 'Zoom out',
                  onPressed: () => _zoom(-0.25),
                ),
                Center(
                  child: Text(
                    '${(_currentZoom * 100).round()}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_in),
                  tooltip: 'Zoom in',
                  onPressed: () => _zoom(0.25),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reset zoom',
                  onPressed: () => _zoomTo(1.0),
                ),
              ],
      ),
      body: kIsWeb ? _buildWebPdfViewer() : _buildMobilePdfViewer(),
      bottomNavigationBar: widget.fileItem != null
          ? BottomAppBar(
              color: Colors.grey.shade900,
              padding: EdgeInsets.zero,
              child: FileActionBar(
                mainAxisAlignment: MainAxisAlignment.center,
                item: widget.fileItem!,
                extraActions: [
                  ActionItem('pdf_to_images', Icons.image_outlined, AppLocalizations.of(context)!.splitToImages),
                ],
                onActionSelected: (action, item) async {
                  if (action == 'pdf_to_images') {
                    _splitToImages(context, item);
                  } else if (action == 'download') {
                    final uri = Uri.parse(item.downloadUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  } else if (action == 'attach') {
                    _api.stageFilesForAi([item.path]);
                  } else {
                    setPdfPointerEvents(false);
                    await Navigator.maybePop(context);
                    widget.onActionSelected?.call(action, item);
                    if (mounted) setPdfPointerEvents(true);
                  }
                },
              ),
            )
          : null,
    );
  }

  Widget _buildWebPdfViewer() {
    registerPdfViewFactory(widget.url);
    return const SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: HtmlElementView(viewType: 'pdf-iframe-view'),
    );
  }

  Widget _buildMobilePdfViewer() {
    final scale = _currentZoom < 1.0 ? _currentZoom : 1.0;

    return Transform.scale(
      scale: scale,
      alignment: Alignment.topCenter,
      child: SfPdfViewer.network(
        widget.url,
        controller: _pdfController,
        onDocumentLoaded: (details) {
          setState(() => _totalPages = details.document.pages.count);
        },
        onPageChanged: (details) {
          setState(() => _currentPage = details.newPageNumber);
        },
        onZoomLevelChanged: (details) {
          setState(() => _currentZoom = details.newZoomLevel);
        },
      ),
    );
  }

  void _zoom(double delta) {
    final next = (_currentZoom + delta).clamp(0.1, 5.0);
    _zoomTo(next);
  }

  void _zoomTo(double level) {
    if (level >= 1.0) {
      _pdfController.zoomLevel = level;
    }
    setState(() => _currentZoom = level);
  }

  void _jumpToPage(int page) {
    _pdfController.jumpToPage(page);
  }

  Future<void> _gotoPageDialog() async {
    final controller = TextEditingController(text: _currentPage.toString());
    final page = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Page (1 – $_totalPages)',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null && n >= 1 && n <= _totalPages) {
                Navigator.pop(ctx, n);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    if (page != null) _jumpToPage(page);
  }

  Future<void> _splitToImages(BuildContext context, FileItem item) async {
    setPdfPointerEvents(false);

    final dirName = await showDialog<String>(
      context: context,
      builder: (ctx) => _SplitToImagesDialog(
        item: item,
        dialogContext: ctx,
      ),
    );

    setPdfPointerEvents(true);

    if (dirName == null || dirName.isEmpty || !mounted) return;

    setPdfPointerEvents(false);

    final navigateTo = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PdfProgressDialog(
        future: _api.pdfToImages(item.path, dirName),
        outputDir: dirName,
      ),
    );

    setPdfPointerEvents(true);

    if (navigateTo != null && mounted) {
      Navigator.pop(context, navigateTo);
    }
  }
}

class _SplitToImagesDialog extends StatefulWidget {
  final FileItem item;
  final BuildContext dialogContext;

  const _SplitToImagesDialog({
    required this.item,
    required this.dialogContext,
  });

  @override
  State<_SplitToImagesDialog> createState() => _SplitToImagesDialogState();
}

class _SplitToImagesDialogState extends State<_SplitToImagesDialog> {
  late String outputDir;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final slash = item.path.lastIndexOf('/');
    final parent = slash >= 0 ? item.path.substring(0, slash) : '';
    final baseName = item.name.replaceAll(RegExp(r'\.[^.]+$'), '');
    outputDir = parent.isEmpty ? baseName : '$parent/$baseName';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.splitToImages),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.outputDirLabel, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    outputDir,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(l10n.selectFolder),
                onPressed: () async {
                  final result = await showModalBottomSheet<String>(
                    context: widget.dialogContext,
                    isScrollControlled: true,
                    builder: (context) => FractionallySizedBox(
                      heightFactor: 0.9,
                      child: NasDirPicker(initialDir: outputDir),
                    ),
                  );
                  if (result != null) {
                    setState(() => outputDir = result);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(l10n.outputDirHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(widget.dialogContext),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(widget.dialogContext, outputDir),
          child: Text(l10n.startButton),
        ),
      ],
    );
  }
}

class _PdfProgressDialog extends StatefulWidget {
  final Future<Map<String, dynamic>> future;
  final String outputDir;

  const _PdfProgressDialog({required this.future, required this.outputDir});

  @override
  State<_PdfProgressDialog> createState() => _PdfProgressDialogState();
}

class _PdfProgressDialogState extends State<_PdfProgressDialog> {
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.future.then((r) {
      if (mounted) setState(() => _result = r);
    }).catchError((e) {
      if (mounted) {
        final message = e.toString();
        // Extract structured error from backend JSON response if possible
        final detailMatch = RegExp(r'"detail":"([^"]+)"').firstMatch(message);
        final friendly = detailMatch != null ? detailMatch.group(1)! : message;
        setState(() => _error = friendly);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _result?['total_pages'] as int? ?? 0;
    final images = (_result?['images'] as List<dynamic>?) ?? [];
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Row(
        children: [
          if (_result == null && _error == null)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          if (_result != null)
            Icon(Icons.check_circle, color: Colors.green.shade600),
          if (_error != null)
            Icon(Icons.error, color: Colors.red.shade600),
          const SizedBox(width: 8),
          Text(l10n.splitToImages),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                  const SizedBox(height: 8),
                  Text('${l10n.outputDirLabel}: ${widget.outputDir}',
                      style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey.shade600)),
                ],
              )
            : _result != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.pagesConverted(totalPages)),
                      const SizedBox(height: 6),
                      Text('${l10n.outputDirLabel}: ${widget.outputDir}',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      const SizedBox(height: 12),
                      if (images.isNotEmpty) ...[
                        Text(l10n.generatedFilesTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        ...images.take(20).map((img) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '  ${img['filename']}',
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          ),
                        )),
                        if (images.length > 20)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(l10n.andMore(images.length - 20),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ),
                      ],
                    ],
                  )
                : Text(l10n.convertingPdf),
      ),
      actions: [
        if (_result != null)
          TextButton.icon(
            icon: const Icon(Icons.folder_open, size: 18),
            onPressed: () => Navigator.pop(context, widget.outputDir),
            label: Text(l10n.openFolder),
          ),
        TextButton(
          onPressed: _result != null || _error != null ? () => Navigator.pop(context) : null,
          child: Text(l10n.okButton),
        ),
      ],
    );
  }
}
