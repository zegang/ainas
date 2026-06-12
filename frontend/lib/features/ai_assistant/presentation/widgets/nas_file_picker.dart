import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:intl/intl.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../services/api_service.dart';
import '../../../file_browser/presentation/widgets/breadcrumb_bar.dart';
import '../../../../shared/models/file_item.dart';

class NasFilePicker extends StatefulWidget {
  final List<String> initialSelectedFiles;

  const NasFilePicker({super.key, this.initialSelectedFiles = const []});

  @override
  State<NasFilePicker> createState() => _NasFilePickerState();
}

class _NasFilePickerState extends State<NasFilePicker> {
  final _log = Logger('NasFilePicker');
  final ApiService api = ApiService();
  List<String> _pathStack = [""];
  late Future<List<FileItem>> _fileListFuture;
  final Set<String> _currentSelection = {}; // Store full paths of selected files

  @override
  void initState() {
    super.initState();
    _currentSelection.addAll(widget.initialSelectedFiles);
    _refreshFileList();
  }

  void _refreshFileList() {
    setState(() {
      _fileListFuture = api.listFiles(_pathStack.last);
    });
  }

  void _onItemTap(FileItem item) {
    if (item.isDir) {
      setState(() {
        _pathStack.add(_pathStack.last.isEmpty ? item.name : "${_pathStack.last}/${item.name}");
      });
      _refreshFileList();
    } else {
      // Toggle selection for files
      final fullPath = _pathStack.last.isEmpty ? item.name : "${_pathStack.last}/${item.name}";
      setState(() {
        if (_currentSelection.contains(fullPath)) {
          _currentSelection.remove(fullPath);
        } else {
          _currentSelection.add(fullPath);
        }
      });
    }
  }

  void _onPathPressed(int index) {
    setState(() {
      _pathStack = _pathStack.sublist(0, index + 1);
    });
    _refreshFileList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.selectFiles),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context), // Close without selecting
        ),
        actions: [
          TextButton(
            onPressed: _currentSelection.isEmpty
                ? null
                : () => Navigator.pop(context, _currentSelection.toList()),
            child: Text(l10n.selectButton(_currentSelection.length)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            child: Row(
              children: [
                if (_pathStack.length > 1)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      setState(() => _pathStack.removeLast());
                      _refreshFileList();
                    },
                  ),
                Expanded(
                  child: BreadcrumbBar(
                    pathStack: _pathStack,
                    onPathPressed: _onPathPressed,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: l10n.refreshTooltip,
                  onPressed: _refreshFileList,
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<FileItem>>(
              future: _fileListFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final items = snapshot.data ?? [];
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final fullPath = _pathStack.last.isEmpty ? item.name : "${_pathStack.last}/${item.name}";
                    final isSelected = _currentSelection.contains(fullPath);
                    return ListTile(
                      leading: Icon(item.isDir ? Icons.folder : Icons.insert_drive_file),
                      title: Text(item.name),
                      subtitle: item.isDir
                          ? null
                          : Text(
                              '${(item.size / 1024).toStringAsFixed(2)} KB - '
                              '${DateFormat.yMd().add_jm().format(item.updatedAt)}',
                            ),
                      trailing: item.isDir
                          ? null
                          : (isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null),
                      onTap: () => _onItemTap(item),
                      selected: isSelected,
                      enabled: !item.isDir, // Only files can be selected
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}