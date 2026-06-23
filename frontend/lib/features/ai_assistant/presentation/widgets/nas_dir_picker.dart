import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/shared/widgets/breadcrumb_bar.dart';
import 'package:ainas_frontend/shared/widgets/file_list_view.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';

class NasDirPicker extends StatefulWidget {
  final String initialDir;

  const NasDirPicker({super.key, this.initialDir = ''});

  @override
  State<NasDirPicker> createState() => _NasDirPickerState();
}

class _NasDirPickerState extends State<NasDirPicker> {
  final _log = Logger('NasDirPicker');
  final ApiService api = ApiService();
  List<String> _pathStack = [""];
  late Future<List<FileItem>> _fileListFuture;
  final Set<FileItem> _selectedItems = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialDir.isNotEmpty) {
      _pathStack = ["", ...widget.initialDir.split('/').where((p) => p.isNotEmpty)];
    }
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
    }
  }

  void _onPathPressed(int index) {
    setState(() {
      _pathStack = _pathStack.sublist(0, index + 1);
      _selectedItems.clear();
    });
    _refreshFileList();
  }

  String get _currentDir {
    return _pathStack.last;
  }

  void _selectCurrentDir() {
    Navigator.pop(context, _currentDir);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.selectFolderTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _selectCurrentDir,
            child: Text(l10n.selectFolder),
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
                  onSelectAll: (val) {},
                  onItemSelected: (item, val) {},
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
