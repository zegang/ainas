import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';
import 'package:ainas_frontend/shared/widgets/breadcrumb_bar.dart';
import 'package:ainas_frontend/services/api_service.dart';

class FolderPickerDialog extends StatefulWidget {
  final String currentPath;
  const FolderPickerDialog({super.key, this.currentPath = ''});

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  final _log = Logger('FolderPickerDialog');
  final ApiService api = ApiService();
  List<String> _pathStack = [];
  late Future<List<FileItem>> _folderFuture;

  @override
  void initState() {
    super.initState();
    _pathStack = widget.currentPath.isNotEmpty ? ['', ...widget.currentPath.split('/').where((s) => s.isNotEmpty)] : [''];
    _refresh();
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
      _pathStack.add(_pathStack.last.isEmpty ? dir.name : '${_pathStack.last}/${dir.name}');
    });
    _refresh();
  }

  void _selectCurrent() {
    Navigator.of(context).pop(_pathStack.last);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 500, maxHeight: 520),
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
                  Icon(Icons.drive_file_move_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(l10n.moveTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
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
                    child: BreadcrumbBar(pathStack: _pathStack, onPathPressed: _navigateTo),
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
                      child: Text(l10n.folderEmpty, style: TextStyle(color: cs.onSurfaceVariant)),
                    );
                  }
                  return ListView.separated(
                    itemCount: folders.length,
                    separatorBuilder: (_, __) => Divider(height: 1, indent: 56, color: cs.outlineVariant),
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.secondaryContainer,
                          child: Icon(Icons.folder, size: 24, color: cs.onSecondaryContainer),
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
                      onPressed: _selectCurrent,
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(l10n.moveHere),
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
