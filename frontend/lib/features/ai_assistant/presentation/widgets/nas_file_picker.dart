import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/shared/widgets/breadcrumb_bar.dart';
import 'package:ainas_frontend/shared/widgets/file_list_view.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';

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
  final Set<FileItem> _selectedItems = {}; // For FileListView selection support

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
        _selectedItems.clear();
      });
      _refreshFileList();
    } else {
      // Toggle selection for files
      final fullPath = _pathStack.last.isEmpty ? item.name : "${_pathStack.last}/${item.name}";
      setState(() {
        if (_currentSelection.contains(fullPath)) {
          _currentSelection.remove(fullPath);
          _selectedItems.remove(item);
        } else {
          _currentSelection.add(fullPath);
          _selectedItems.add(item);
        }
      });
    }
  }

  void _onPathPressed(int index) {
    setState(() {
      _pathStack = _pathStack.sublist(0, index + 1);
      _selectedItems.clear();
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
                return FileListView(
                  items: items,
                  sortColumnIndex: 0,
                  sortAscending: true,
                  onSort: (index, ascending) {},
                  onItemTap: _onItemTap,
                  onActionSelected: (action, item) {},
                  selectedItems: _selectedItems,
                  onSelectAll: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedItems.clear();
                        _selectedItems.addAll(items.where((item) => !item.isDir));
                        _currentSelection.clear();
                        _currentSelection.addAll(items.where((item) => !item.isDir).map((item) => _pathStack.last.isEmpty ? item.name : "${_pathStack.last}/${item.name}"));
                      } else {
                        _selectedItems.clear();
                        _currentSelection.clear();
                      }
                    });
                  },
                  onItemSelected: (item, val) {
                    final fullPath = _pathStack.last.isEmpty ? item.name : "${_pathStack.last}/${item.name}";
                    setState(() {
                      if (val == true) {
                        _selectedItems.add(item);
                        _currentSelection.add(fullPath);
                      } else {
                        _selectedItems.remove(item);
                        _currentSelection.remove(fullPath);
                      }
                    });
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