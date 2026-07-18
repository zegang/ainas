import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';
import 'package:ainas_frontend/shared/widgets/file_action_menu.dart';
import 'package:ainas_frontend/services/api_service.dart';

class ImageViewerPage extends StatefulWidget {
  final String thumbnailUrl;
  final String originalUrl;
  final String title;
  final int fileSize;
  final FileItem fileItem;
  final void Function(String action, FileItem item) onActionSelected;

  const ImageViewerPage({
    super.key,
    required this.thumbnailUrl,
    required this.originalUrl,
    required this.title,
    required this.fileSize,
    required this.fileItem,
    required this.onActionSelected,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final _api = ApiService();
  bool _showOriginal = false;
  int? _compressedSize;
  int? _imageWidth;
  int? _imageHeight;

  Future<void> _resolveImageSize() async {
    if (_imageWidth != null) return;
    try {
      final completer = Completer<ui.Image>();
      final stream = NetworkImage(widget.originalUrl).resolve(ImageConfiguration.empty);
      stream.addListener(ImageStreamListener((ImageInfo info, bool sync) {
        completer.complete(info.image);
      }));
      final image = await completer.future;
      if (mounted) {
        setState(() {
          _imageWidth = image.width;
          _imageHeight = image.height;
        });
      }
    } catch (_) {
    }
  }

  @override
  void initState() {
    super.initState();
    _resolveImageSize();
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return "---";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return ((bytes / math.pow(1024, i)).toStringAsFixed(1)) + ' ' + suffixes[i];
  }

  Future<void> _showCompressDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final path = widget.fileItem.path;
    final slash = path.lastIndexOf('/');
    final parent = slash >= 0 ? path.substring(0, slash) : '';
    final base = path.contains('.')
        ? path.substring(0, path.lastIndexOf('.'))
        : path;
    final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')) : '';

    final w = _imageWidth ?? 0;
    final h = _imageHeight ?? 0;
    final qualityController = TextEditingController(text: '85');
    final widthController = TextEditingController(text: w > 0 ? '$w' : '0');
    final heightController = TextEditingController(text: h > 0 ? '$h' : '0');
    final outputNameController = TextEditingController(text: '${base}_compressed$ext');
    bool compressing = false;
    bool saveAsCopy = true;
    Map<String, dynamic>? result;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.compressImageTitle),
          content: result != null
              ? _buildCompressResult(result!, l10n)
              : compressing
                  ? const SizedBox(
                      width: 60,
                      height: 60,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (w > 0 && h > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${l10n.currentDimensionLabel}: ${w}x$h',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          Text(
                            '${l10n.currentSizeLabel}: ${_formatSize(_compressedSize ?? widget.fileSize)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: widthController,
                                  decoration: InputDecoration(
                                    labelText: l10n.compressWidthLabel,
                                    border: const OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: heightController,
                                  decoration: InputDecoration(
                                    labelText: l10n.compressHeightLabel,
                                    border: const OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: qualityController,
                            decoration: InputDecoration(
                              labelText: l10n.compressQualityLabel,
                              helperText: l10n.compressQualityHint,
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.compressSaveAsCopyLabel),
                            subtitle: Text(saveAsCopy
                                ? l10n.compressSaveAsCopyHint
                                : l10n.compressOverwriteHint),
                            value: saveAsCopy,
                            onChanged: (v) => setDialogState(() => saveAsCopy = v),
                          ),
                          if (saveAsCopy)
                            TextField(
                              controller: outputNameController,
                              decoration: InputDecoration(
                                labelText: l10n.compressOutputNameLabel,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                        ],
                      ),
                    ),
          actions: [
            if (result == null)
              TextButton(
                onPressed: compressing ? null : () => Navigator.pop(ctx),
                child: Text(l10n.cancelButton),
              ),
            if (result != null)
              TextButton(
                onPressed: () {
                  _compressedSize = result!['compressed_size'] as int?;
                  Navigator.pop(ctx);
                },
                child: Text(l10n.okButton),
              ),
            if (result == null)
              FilledButton(
                onPressed: compressing
                    ? null
                    : () async {
                        final quality = int.tryParse(qualityController.text) ?? 85;
                        final targetW = int.tryParse(widthController.text) ?? 0;
                        final targetH = int.tryParse(heightController.text) ?? 0;
                        if (quality < 1 || quality > 100) return;

                        setDialogState(() => compressing = true);
                        try {
                          String? outputPath;
                          if (saveAsCopy) {
                            outputPath = parent.isEmpty
                                ? outputNameController.text
                                : '$parent/${outputNameController.text}';
                          }
                          final r = await _api.compressImage(
                            path,
                            quality,
                            maxWidth: targetW > 0 ? targetW : null,
                            maxHeight: targetH > 0 ? targetH : null,
                            outputPath: outputPath,
                          );
                          _compressedSize = r['compressed_size'] as int?;
                          setDialogState(() => result = r);
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('${l10n.compressFailed}: $e')),
                            );
                          }
                          Navigator.pop(ctx);
                        }
                      },
                child: Text(l10n.compressButton),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompressResult(Map<String, dynamic> r, AppLocalizations l10n) {
    final orig = r['original_size'] as int? ?? 0;
    final comp = r['compressed_size'] as int? ?? 0;
    final pct = orig > 0 ? ((orig - comp) * 100 / orig).toStringAsFixed(1) : '0';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
          const SizedBox(width: 8),
          Text(l10n.compressSuccessTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 12),
        Text('${l10n.originalSizeLabel}: ${_formatSize(orig)}'),
        Text('${l10n.compressedSizeLabel}: ${_formatSize(comp)}'),
        Text('${l10n.reductionLabel}: $pct%'),
        Text('${l10n.compressQualityLabel}: ${r['quality']}'),
        Text('${l10n.compressDimensionLabel}: ${r['width']}x${r['height']}'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tags = widget.fileItem.tags;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.compress),
            tooltip: l10n.compressImageTooltip,
            onPressed: _showCompressDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: _showOriginal ? widget.originalUrl : widget.thumbnailUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white54),
                    ),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.broken_image,
                      size: 80,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
            if (!_showOriginal)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showOriginal = true;
                    });
                  },
                  icon: const Icon(Icons.image_search, color: Colors.white70),
                  label: Text(
                    l10n.viewOriginalImage(_formatSize(widget.fileSize)),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            if (tags.isNotEmpty)
              Container(
                width: double.infinity,
                color: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: tags.map((tag) => Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(tag, style: TextStyle(fontSize: 14, color: cs.onPrimaryContainer)),
                          )).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.grey.shade900,
        padding: EdgeInsets.zero,
        child: FileActionBar(
          mainAxisAlignment: MainAxisAlignment.center,
          item: widget.fileItem,
          onActionSelected: (action, item) {
            Navigator.maybePop(context);
            widget.onActionSelected(action, item);
          },
        ),
      ),
    );
  }
}