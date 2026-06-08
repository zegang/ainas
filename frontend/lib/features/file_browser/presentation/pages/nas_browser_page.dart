import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nsd/nsd.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logging/logging.dart';
import 'package:intl/intl.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../common/themes/app_theme.dart';
import '../../../../services/api_service.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/file_grid_view.dart';
import '../widgets/file_list_view.dart';
import '../widgets/upload_overlay.dart';

class NASBrowser extends StatefulWidget {
  const NASBrowser({super.key});

  @override
  State<NASBrowser> createState() => _NASBrowserState();
}

class _NASBrowserState extends State<NASBrowser> {
  final _log = Logger('NASBrowser');
  final ApiService api = ApiService();
  List<String> pathStack = [""];
  late Future<List<FileItem>> _fileList;
  bool _isDiscovering = true;
  bool _isGridView = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  int _sortColumnIndex = 0; // 0: Name, 1: Size, 2: Type, 3: Date
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _initDiscovery();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initDiscovery() async {
    if (kIsWeb) {
      setState(() => _isDiscovering = false);
      _refresh();
      return;
    }

    _log.info('Starting Network Service Discovery (mDNS)...');
    Future.delayed(const Duration(seconds: 5), () {
      if (_isDiscovering && mounted) {
        _log.info('Discovery timed out after 5s, using fallback/manual URL.');
        setState(() => _isDiscovering = false);
        _refresh();
      }
    });

    try {
      final discovery = await startDiscovery('_http._tcp');
      discovery.addListener(() {
        for (final service in discovery.services) {
          if (service.name != null && service.name!.contains('AINAS')) {
            _log.info('Service found: ${service.name} at ${service.host}:${service.port}');
            final host = service.host ?? 'localhost';
            final port = service.port ?? 9026;
            if (mounted) {
              setState(() {
                api.baseUrl = "http://$host:$port";
                _isDiscovering = false;
              });
              _refresh();
            }
            stopDiscovery(discovery);
            break;
          }
        }
      });
    } catch (e, st) {
      _log.warning('Network discovery failed or not supported: $e. Falling back to default URL.', e, st);
      if (mounted && _isDiscovering) {
        setState(() => _isDiscovering = false);
        _refresh();
      }
    }
  }

  void _refresh() {
    setState(() {
      _fileList = api.listFiles(pathStack.last);
    });
  }

  Future<void> _handleUpload() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        for (var file in result.files) {
          if (file.bytes != null) {
            api.uploadFile(file.name, file.bytes!).then((_) => _refresh());
          }
        }
      }
    } catch (e, st) {
      _log.severe('Upload failed', e, st);
    }
  }

  Future<void> _handleFolderUpload() async {
    if (kIsWeb) {
      _log.warning('Folder selection is not supported on Web via FilePicker');
      return;
    }

    try {
      // 1. Pick the directory path
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        final dir = Directory(selectedDirectory);
        final parentPath = dir.parent.path;

        // 2. Stream all entities recursively
        final List<Future<void>> uploadFutures = [];
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            final bytes = await entity.readAsBytes();
            
            // 3. Calculate relative path to preserve folder structure on the server
            // e.g., "my_folder/sub_dir/file.txt"
            final relativePath = entity.path.substring(parentPath.length).replaceFirst(RegExp(r'^[/\\]'), '');
            
            // 4. Trigger upload task
            uploadFutures.add(api.uploadFile(relativePath, bytes));
          }
        }
        
        _log.info('Started uploading ${uploadFutures.length} files from $selectedDirectory');
        await Future.wait(uploadFutures);
        _refresh();
      }
    } catch (e, st) {
      _log.severe('Folder upload failed', e, st);
    }
  }

  Future<void> _handleCreateFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final folderName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newFolderTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.newFolderHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelButton)),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.createButton),
          ),
        ],
      ),
    );

    if (folderName != null && folderName.isNotEmpty) {
      final fullPath = pathStack.last.isEmpty ? folderName : "${pathStack.last}/$folderName";
      await api.createFolder(fullPath);
      _refresh();
    }
  }

  void _sortItems(List<FileItem> items) {
    items.sort((a, b) {
      // Industry standard: Keep folders at the top
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;

      int cmp;
      switch (_sortColumnIndex) {
        case 0: // Name
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case 1: // Size
          cmp = a.size.compareTo(b.size);
          break;
        case 2: // Type
          String typeA = a.isDir ? 'Folder' : (a.name.contains('.') ? a.name.split('.').last : 'File');
          String typeB = b.isDir ? 'Folder' : (b.name.contains('.') ? b.name.split('.').last : 'File');
          cmp = typeA.compareTo(typeB);
          break;
        case 3: // Date
          cmp = a.updatedAt.compareTo(b.updatedAt);
          break;
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  Future<void> _handleDelete(FileItem item) async {
    final fullPath = pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}";
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text("Are you sure you want to delete ${item.name}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await api.deleteItem(fullPath);
        _refresh();
      } catch (e) {
        _log.severe("Delete failed", e);
      }
    }
  }

  Future<void> _handleRename(FileItem item) async {
    final fullPath = pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}";
    final controller = TextEditingController(text: item.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Rename"),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text("Rename")),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != item.name) {
      await api.renameItem(fullPath, newName);
      _refresh();
    }
  }

  Future<void> _handleMove(FileItem item) async {
    final fullPath = pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}";
    final controller = TextEditingController(text: fullPath);
    final newPath = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Move Item"),
        content: TextField(controller: controller, decoration: const InputDecoration(helperText: "Enter full target path")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text("Move")),
        ],
      ),
    );
    if (newPath != null && newPath.isNotEmpty && newPath != fullPath) {
      await api.moveItem(fullPath, newPath);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;

    final toolBar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Row(
        children: [
          if (pathStack.length > 1)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() => pathStack.removeLast());
                _refresh();
              },
            ),
          Expanded(
            child: _isSearching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(hintText: l10n.searchHint, border: InputBorder.none),
                    onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                  )
                : BreadcrumbBar(
                    pathStack: pathStack,
                    onPathPressed: (index) {
                      setState(() {
                        pathStack = pathStack.sublist(0, index + 1);
                      });
                      _refresh();
                    },
                  ),
          ),
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchQuery = "";
                _searchController.clear();
              }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: l10n.newFolderTitle,
            onPressed: _handleCreateFolder,
          ),
          if (!kIsWeb) // Hide folder upload on web
            IconButton(
              icon: const Icon(Icons.drive_folder_upload),
              tooltip: "Upload Folder",
              onPressed: _handleFolderUpload,
            ),
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            tooltip: _isGridView ? "Switch to List" : "Switch to Grid",
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refreshTooltip,
            onPressed: _refresh,
          ),
        ],
      ),
    );

    return Scaffold(
      body: Column(
        children: [
          toolBar,
          Expanded(
            child: _isDiscovering
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<FileItem>>(
              future: _fileList,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off, size: 80, color: Theme.of(context).colorScheme.error.withOpacity(0.5)),
                          const SizedBox(height: 24),
                          Text(
                            "Connection Failed",
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Unable to communicate with the NAS server. Please ensure the server is running and your network settings are correct.",
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          FilledButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text("Retry Connection"),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final items = (snapshot.data ?? []).where((item) {
                  return _searchQuery.isEmpty ||
                      item.name.toLowerCase().contains(_searchQuery) ||
                      item.tags.any((tag) => tag.toLowerCase().contains(_searchQuery));
                }).toList();

                _sortItems(items);

                if (_isGridView) {
                  return FileGridView(
                    items: items,
                    onItemTap: _onItemTap,
                    onActionSelected: (action, item) => _handleAction(action, item),
                  );
                } else {
                  return FileListView(
                    items: items,
                    sortColumnIndex: _sortColumnIndex,
                    sortAscending: _sortAscending,
                    onSort: (index, ascending) {
                      setState(() {
                        _sortColumnIndex = index;
                        _sortAscending = ascending;
                      });
                    },
                    onItemTap: _onItemTap,
                    onActionSelected: (action, item) => _handleAction(action, item),
                  );
                }
              },
            ),
          ),
        ],
      ),
      bottomSheet: UploadOverlay(api: api),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60.0), // Avoid overlap with upload widget
        child: FloatingActionButton.extended(
          onPressed: _handleUpload,
          label: Text(l10n.uploadLabel),
          icon: const Icon(Icons.upload_file),
        ),
      ),
    );
  }

  void _handleAction(String action, FileItem item) {
    if (action == 'rename') _handleRename(item);
    if (action == 'move') _handleMove(item);
    if (action == 'delete') _handleDelete(item);
  }

  void _onItemTap(FileItem item) {
    if (item.isDir) {
      setState(() => pathStack.add(pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}"));
      _refresh();
    }
  }
}