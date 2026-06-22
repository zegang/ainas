import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';
import 'package:ainas_frontend/shared/widgets/file_action_menu.dart';

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
  bool _showOriginal = false;

  String _formatSize(int bytes) {
    if (bytes <= 0) return "---";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return ((bytes / math.pow(1024, i)).toStringAsFixed(1)) + ' ' + suffixes[i];
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
                    Icon(Icons.auto_awesome, size: 14, color: cs.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: tags.map((tag) => Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(tag, style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
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