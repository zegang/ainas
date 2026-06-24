import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';
import 'package:ainas_frontend/shared/widgets/breadcrumb_bar.dart';
import 'package:ainas_frontend/services/api_service.dart';

class MergeToPdfDialog extends StatefulWidget {
  final String currentPath;
  final List<String> filePaths;

  const MergeToPdfDialog({
    super.key,
    this.currentPath = '',
    required this.filePaths,
  });

  @override
  State<MergeToPdfDialog> createState() => _MergeToPdfDialogState();
}

class _MergeToPdfDialogState extends State<MergeToPdfDialog> {
  final _log = Logger('MergeToPdfDialog');
  final ApiService api = ApiService();
  final _filenameController = TextEditingController(text: 'merged.pdf');
  late List<String> _filePaths;
  List<String> _pathStack = [];
  late Future<List<FileItem>> _folderFuture;

  String _thumbnailUrl(String path) =>
      '${api.baseUrl}/api/files/download?path=${Uri.encodeComponent(path)}&thumbnail=true';

  static final _imageExts = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'};

  bool _isImage(String path) {
    final lower = path.toLowerCase();
    return _imageExts.any((e) => lower.endsWith(e));
  }

  bool _isPdf(String path) => path.toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    _filePaths = List.from(widget.filePaths);
    _pathStack = widget.currentPath.isNotEmpty
        ? ['', ...widget.currentPath.split('/').where((s) => s.isNotEmpty)]
        : [''];
    _refresh();
  }

  @override
  void dispose() {
    _filenameController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _folderFuture = api.listFiles(_pathStack.last).then(
        (items) => items.where((f) => f.isDir).toList(),
      );
    });
  }

  void _navigateTo(int index) {
    setState(() => _pathStack = _pathStack.sublist(0, index + 1));
    _refresh();
  }

  void _navigateInto(FileItem dir) {
    setState(() {
      _pathStack.add(
        _pathStack.last.isEmpty ? dir.name : '${_pathStack.last}/${dir.name}',
      );
    });
    _refresh();
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final temp = _filePaths[index];
      _filePaths[index] = _filePaths[index - 1];
      _filePaths[index - 1] = temp;
    });
  }

  void _moveDown(int index) {
    if (index >= _filePaths.length - 1) return;
    setState(() {
      final temp = _filePaths[index];
      _filePaths[index] = _filePaths[index + 1];
      _filePaths[index + 1] = temp;
    });
  }

  void _removeFile(int index) {
    setState(() => _filePaths.removeAt(index));
  }

  void _submit() {
    final filename = _filenameController.text.trim();
    if (filename.isEmpty) return;
    Navigator.of(context).pop({
      'folder': _pathStack.last,
      'filename': filename,
      'file_paths': _filePaths,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final countStr = _filePaths.length.toString();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 540, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.3),
                border: Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf, size: 20),
                  const SizedBox(width: 8),
                  Text(l10n.mergeToPdfDialogTitle,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.mergeToPdfCount(countStr)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _filenameController,
                    decoration: InputDecoration(
                      labelText: l10n.mergeToPdfFilename,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: cs.surfaceContainerHighest.withOpacity(0.15),
              child: Text(l10n.mergePdfsOrderHint,
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant)),
            ),
            SizedBox(
              height: 260,
              child: ReorderableListView.builder(
                itemCount: _filePaths.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _filePaths.removeAt(oldIndex);
                    _filePaths.insert(newIndex, item);
                  });
                },
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final path = _filePaths[index];
                  final name = path.split('/').last;
                  return Column(
                    key: ValueKey(path),
                    children: [
                      if (index > 0)
                        Divider(height: 1, indent: 72, color: cs.outlineVariant),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                            const SizedBox(width: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: _isImage(path)
                                    ? Image.network(
                                        _thumbnailUrl(path),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.broken_image, size: 32),
                                        loadingBuilder: (_, child, progress) =>
                                            progress == null
                                                ? child
                                                : const SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child: CircularProgressIndicator(
                                                        strokeWidth: 2),
                                                  ),
                                      )
                                    : Center(
                                        child: Icon(Icons.picture_as_pdf,
                                            size: 28,
                                            color: cs.error),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          _isImage(path) ? l10n.imageType : l10n.pdfType,
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_up,
                                  size: 20),
                              visualDensity: VisualDensity.compact,
                              onPressed:
                                  index > 0 ? () => _moveUp(index) : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down,
                                  size: 20),
                              visualDensity: VisualDensity.compact,
                              onPressed: index < _filePaths.length - 1
                                  ? () => _moveDown(index)
                                  : null,
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.remove_circle_outline,
                                  size: 20, color: cs.error),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _removeFile(index),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: cs.surfaceContainerHighest.withOpacity(0.2),
              child: Row(
                children: [
                  if (_pathStack.length > 1)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() => _pathStack.removeLast());
                        _refresh();
                      },
                    ),
                  Expanded(
                    child: BreadcrumbBar(
                        pathStack: _pathStack, onPathPressed: _navigateTo),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<FileItem>>(
                future: _folderFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final folders = snapshot.data ?? [];
                  if (folders.isEmpty) {
                    return Center(
                      child: Text(l10n.folderEmpty,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    );
                  }
                  return ListView.separated(
                    itemCount: folders.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, indent: 56, color: cs.outlineVariant),
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.secondaryContainer,
                          child: Icon(Icons.folder,
                              size: 24, color: cs.onSecondaryContainer),
                        ),
                        title: Text(folder.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _navigateInto(folder),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(l10n.cancelButton),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: Text(l10n.mergeToPdfAction),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
