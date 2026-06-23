import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nsd/nsd.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logging/logging.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/themes/app_theme.dart';
import 'package:ainas_frontend/services/api_service.dart';
import '../controllers/file_browser_controller.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';
import 'package:ainas_frontend/shared/widgets/breadcrumb_bar.dart';
import 'package:ainas_frontend/shared/widgets/file_grid_view.dart';
import 'package:ainas_frontend/shared/widgets/file_list_view.dart';
import 'package:ainas_frontend/features/file_browser/presentation/widgets/file_filter_sheet.dart';
import 'package:ainas_frontend/features/ai_assistant/presentation/widgets/ai_assistant_page.dart';
import 'package:ainas_frontend/shared/widgets/viewers/pdf_viewer_page.dart';
import 'package:ainas_frontend/shared/widgets/viewers/docx_viewer_page.dart';
import 'package:ainas_frontend/shared/widgets/viewers/image_viewer_page.dart';
import 'upload_overlay.dart';
import 'folder_picker_dialog.dart';

class NASBrowser extends StatefulWidget {
  const NASBrowser({super.key});

  @override
  State<NASBrowser> createState() => _NASBrowserState();
}

class _NASBrowserState extends State<NASBrowser> {
  final _log = Logger('NASBrowser');
  final ApiService api = ApiService();
  final FileBrowserController _controller = FileBrowserController();
  List<String> pathStack = [""];
  late Future<List<FileItem>> _fileList;
  bool _isDiscovering = true;
  bool _isGridView = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  int _sortColumnIndex = 0; // 0: Name, 1: Size, 2: Type, 3: Date
  bool _sortAscending = true;
  final Set<FileItem> _selectedItems = {};
  final List<FileItem> _currentItems = [];
  Map<String, dynamic> _fileFilter = {}; // e.g. { 'types': Set<String>, 'tags': 'a,b' }
  Set<String> _availableTags = {};
  Timer? _pollTimer;
  int _pollAttempts = 0;
  static const int _maxPollAttempts = 12;
  static const Duration _pollInterval = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    _initDiscovery();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _stopPolling();
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

  void _refresh({bool forceRefresh = false}) {
    setState(() {
      _selectedItems.clear();
      _fileList = api.listFiles(pathStack.last, forceRefresh: forceRefresh);
    });
    // Periodically poll for tag updates when files may be processing
    _startPolling();
  }

  Future<void> _handleUpload() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        for (var file in result.files) {
          if (file.bytes != null) {
            api.uploadFile(file.name, file.bytes!).then((_) => _refresh(forceRefresh: true));
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
      String? selectedDirectory = await FilePicker.getDirectoryPath();

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
        _refresh(forceRefresh: true);
      }
    } catch (e, st) {
      _log.severe('Folder upload failed', e, st);
    }
  }

  Future<void> _openTransfers() async {
    // Show the transfer/upload overlay as a modal bottom sheet
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.6,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
          ),
          child: UploadOverlay(api: api),
        ),
      ),
    );
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
      _refresh(forceRefresh: true);
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
    final l10n = AppLocalizations.of(context)!;
    final fullPath = pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}";
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmMessage(item.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancelButton)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.deleteButton, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await api.deleteItem(fullPath);
        _refresh(forceRefresh: true);
      } catch (e) {
        _log.severe("Delete failed", e);
      }
    }
  }

  Future<void> _handleRename(FileItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final fullPath = pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}";
    final controller = TextEditingController(text: item.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelButton)),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(l10n.renameAction)),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != item.name) {
      await api.renameItem(fullPath, newName);
      _refresh(forceRefresh: true);
    }
  }

  Future<void> _handleMove(FileItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final fullPath = pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}";
    final targetDir = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(currentPath: pathStack.last),
    );
    if (targetDir != null && targetDir.isNotEmpty && targetDir != pathStack.last) {
      final newPath = targetDir.isEmpty ? item.name : "$targetDir/${item.name}";
      await api.moveItem(fullPath, newPath);
      _refresh(forceRefresh: true);
    }
  }

  Future<void> _handleBatchDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final count = _selectedItems.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteBatchConfirmTitle),
        content: Text(l10n.deleteBatchConfirmMessage(count)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancelButton)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.deleteButton, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final futures = _selectedItems.map((item) {
          final fullPath = pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}";
          return api.deleteItem(fullPath);
        });
        await Future.wait(futures);
        _refresh(forceRefresh: true);
      } catch (e) {
        _log.severe("Batch delete failed", e);
      }
    }
  }

  void _handleAttachToAi(FileItem item) {
    final fullPath = pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}";
    api.stageFilesForAi([fullPath]);
    // Switch to the AI Assistant tab (Index 2)
    api.setTabIndex(2);
  }

  void _handleBatchAttachToAi() {
    if (_selectedItems.isEmpty) return;
    
    final paths = _selectedItems.map((item) {
      return pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}";
    }).toList();
    
    api.stageFilesForAi(paths);
    final count = _selectedItems.length;
    setState(() => _selectedItems.clear());
    // Switch to the AI Assistant tab (Index 2)
    api.setTabIndex(2);
  }

  Future<void> _handleBatchMove() async {
    final l10n = AppLocalizations.of(context)!;
    final targetDir = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(currentPath: pathStack.last),
    );
    if (targetDir != null && targetDir.isNotEmpty && targetDir != pathStack.last) {
      final futures = _selectedItems.map((item) {
        final fullPath = pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}";
        final newPath = targetDir.isEmpty ? item.name : "$targetDir/${item.name}";
        return api.moveItem(fullPath, newPath);
      });
      await Future.wait(futures);
      _refresh(forceRefresh: true);
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedItems.length == _currentItems.length) {
        _selectedItems.clear();
      } else {
        _selectedItems.addAll(_currentItems);
      }
    });
  }

  bool _isImageFile(String name) {
    final ext = name.toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']
        .any((s) => ext.endsWith(s));
  }

  bool _anyItemNeedsProcessing(List<FileItem> items) {
    return items.any((item) => !item.isDir && item.tags.isEmpty && _isImageFile(item.name));
  }

  void _startPolling() {
    if (_pollTimer != null) return;
    _pollAttempts = 0;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollTags());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollAttempts = 0;
  }

  Future<void> _pollTags() async {
    if (!mounted) return;
    _pollAttempts++;
    try {
      final updatedItems = await api.listFiles(pathStack.last, forceRefresh: true);
      if (!mounted) return;

      bool tagsChanged = false;
      for (final updated in updatedItems) {
        for (final current in _currentItems) {
          if (current.path == updated.path) {
            if (current.tags.length != updated.tags.length ||
                !current.tags.every(updated.tags.contains)) {
              tagsChanged = true;
              break;
            }
          }
        }
        if (tagsChanged) break;
      }

      if (tagsChanged) {
        _refresh(forceRefresh: true);
      }

      if (_pollAttempts >= _maxPollAttempts || !_anyItemNeedsProcessing(updatedItems)) {
        _stopPolling();
      }
    } catch (e) {
      _log.warning('Tag polling failed: $e');
      if (_pollAttempts >= _maxPollAttempts) _stopPolling();
    }
  }

  Widget _buildDesktopToolBar(BuildContext context, AppLocalizations l10n) {
    return Row(
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
        if (_selectedItems.length > 1) ...[
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: l10n.deleteAction,
            onPressed: _handleBatchDelete,
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move_outlined),
            tooltip: l10n.moveAction,
            onPressed: _handleBatchMove,
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: l10n.attachToAiAction,
            onPressed: _handleBatchAttachToAi,
          ),
          IconButton(
            icon: const Icon(Icons.deselect_outlined),
            tooltip: l10n.clear,
            onPressed: () => setState(() => _selectedItems.clear()),
          ),
        ],
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: l10n.selectAll,
          onPressed: _toggleSelectAll,
        ),
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: l10n.newFolderTitle,
          onPressed: _handleCreateFolder,
        ),
        if (!kIsWeb) // Hide folder upload on web
          IconButton(
            icon: const Icon(Icons.drive_folder_upload),
            tooltip: l10n.uploadFolder,
            onPressed: _handleFolderUpload,
          ),
        // Select files to upload
        IconButton(
          icon: const Icon(Icons.upload_file),
          tooltip: l10n.uploadLabel,
          onPressed: _handleUpload,
        ),
        // Open transfers list
        IconButton(
          icon: const Icon(Icons.list_alt),
          tooltip: l10n.transferList,
          onPressed: _openTransfers,
        ),
        IconButton(
          icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
          tooltip: _isGridView ? l10n.switchViewList : l10n.switchViewGrid,
          onPressed: () => setState(() => _isGridView = !_isGridView),
        ),
        IconButton(
          icon: const Icon(Icons.filter_list),
          tooltip: l10n.filterTooltip,
          onPressed: () async {
            final width = MediaQuery.of(context).size.width;
            if (kIsWeb && width >= 800) {
              final result = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (context) => Dialog(
                  insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: math.min(900, width - 160), maxHeight: 800),
                    child: FileFilterSheet(initial: _fileFilter, availableTags: _availableTags.toList()),
                  ),
                ),
              );
              if (result != null) setState(() => _fileFilter = result);
            } else {
              final result = await showModalBottomSheet<Map<String, dynamic>>(
                context: context,
                isScrollControlled: true,
                builder: (context) => FractionallySizedBox(
                  heightFactor: 0.6,
                  child: FileFilterSheet(initial: _fileFilter, availableTags: _availableTags.toList()),
                ),
              );
              if (result != null) setState(() => _fileFilter = result);
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: l10n.refreshTooltip,
          onPressed: _refresh,
        ),
      ],
    );
  }

  Widget _buildMobileToolBar(BuildContext context, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Row 1: Search
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.searchHint,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                ),
              ),
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _searchQuery = "";
                      _searchController.clear();
                    });
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        
        // Row 2: Path/Breadcrumbs
        Row(
          children: [
            if (pathStack.length > 1)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    pathStack.removeLast();
                    _selectedItems.clear();
                  });
                  _refresh();
                },
              ),
            Expanded(
              child: BreadcrumbBar(
                pathStack: pathStack,
                onPathPressed: (index) {
                  setState(() {
                    pathStack = pathStack.sublist(0, index + 1);
                    _selectedItems.clear();
                  });
                  _refresh();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Row 3: Action icons
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (_selectedItems.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: l10n.deleteAction,
                  onPressed: _handleBatchDelete,
                ),
                IconButton(
                  icon: const Icon(Icons.drive_file_move_outlined),
                  tooltip: l10n.moveAction,
                  onPressed: _handleBatchMove,
                ),
                IconButton(
                  icon: const Icon(Icons.auto_awesome_outlined),
                  tooltip: l10n.attachToAiAction,
                  onPressed: _handleBatchAttachToAi,
                ),
                IconButton(
                  icon: const Icon(Icons.deselect_outlined),
                  tooltip: l10n.clear,
                  onPressed: () => setState(() => _selectedItems.clear()),
                ),
                Container(height: 24, width: 1, color: Colors.grey, margin: const EdgeInsets.symmetric(horizontal: 8)),
              ],
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: l10n.selectAll,
                onPressed: _toggleSelectAll,
              ),
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined),
                tooltip: l10n.newFolderTitle,
                onPressed: _handleCreateFolder,
              ),
              if (!kIsWeb)
                IconButton(
                  icon: const Icon(Icons.drive_folder_upload),
                  tooltip: l10n.uploadFolder,
                  onPressed: _handleFolderUpload,
                ),
              // Select files to upload
              IconButton(
                icon: const Icon(Icons.upload_file),
                tooltip: l10n.uploadLabel,
                onPressed: _handleUpload,
              ),
              // Open transfers list
              IconButton(
                icon: const Icon(Icons.list_alt),
                tooltip: l10n.transferList,
                onPressed: _openTransfers,
              ),
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: l10n.filterTooltip,
                onPressed: () async {
                  final result = await showModalBottomSheet<Map<String, dynamic>>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => FractionallySizedBox(
                      heightFactor: 0.6,
                      child: FileFilterSheet(initial: _fileFilter, availableTags: _availableTags.toList()),
                    ),
                  );
                  if (result != null) {
                    setState(() {
                      _fileFilter = result;
                    });
                  }
                },
              ),
              IconButton(
                icon: Icon(_sortColumnIndex == 3 ? Icons.access_time : Icons.sort_by_alpha),
                tooltip: l10n.sortTooltip,
                onPressed: () => setState(() {
                  if (_sortColumnIndex == 3) {
                    _sortColumnIndex = 0; // name
                  } else {
                    _sortColumnIndex = 3; // date/time
                  }
                }),
              ),
              IconButton(
                icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                tooltip: _isGridView ? l10n.switchViewList : l10n.switchViewGrid,
                onPressed: () {
                  setState(() {
                    _isGridView = !_isGridView;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    final toolBar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: isSmallScreen ? _buildMobileToolBar(context, l10n) : _buildDesktopToolBar(context, l10n),
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
                            l10n.connectionFailedTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.connectionFailedMessage,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          FilledButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.retryConnection),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final rawItems = (snapshot.data ?? []).toList();

                // collect available tags from current view
                final tags = <String>{};
                for (final it in rawItems) {
                  for (final t in it.tags) {
                    if (t.trim().isNotEmpty) tags.add(t.trim());
                  }
                }
                if (tags.length != _availableTags.length || !tags.containsAll(_availableTags)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _availableTags = tags);
                  });
                }

                final items = rawItems.where((item) {
                  final nameMatch = _searchQuery.isEmpty || item.name.toLowerCase().contains(_searchQuery);
                  final tagMatch = _searchQuery.isEmpty || item.tags.any((tag) => tag.toLowerCase().contains(_searchQuery));
                  if (!(nameMatch || tagMatch)) return false;

                  // Type filters
                  if (_fileFilter['types'] != null && (_fileFilter['types'] as Set).isNotEmpty) {
                    if (!item.isDir) {
                      final ext = item.name.contains('.') ? item.name.split('.').last.toLowerCase() : '';
                      final Set types = (_fileFilter['types'] as Set).cast<String>();
                      bool typeMatch = false;
                      if (types.contains('images') && ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) typeMatch = true;
                      if (types.contains('pdf') && ext == 'pdf') typeMatch = true;
                      if (types.contains('docx') && ext == 'docx') typeMatch = true;
                      if (types.contains('others') && !['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'pdf', 'docx'].contains(ext)) typeMatch = true;
                      if (!typeMatch) return false;
                    }
                  }

                  // Tags filter (comma-separated)
                  if (_fileFilter['tags'] != null && (_fileFilter['tags'] as String).trim().isNotEmpty) {
                    final wanted = (_fileFilter['tags'] as String)
                        .split(',')
                        .map((s) => s.trim().toLowerCase())
                        .where((s) => s.isNotEmpty)
                        .toSet();
                    if (wanted.isNotEmpty) {
                      final itemTags = item.tags.map((t) => t.toLowerCase()).toSet();
                      if (itemTags.intersection(wanted).isEmpty) return false;
                    }
                  }

                  return true;
                }).toList();

                _sortItems(items);
                _currentItems
                  ..clear()
                  ..addAll(items);

                if (_isGridView) {
                  return FileGridView(
                    items: items,
                    onItemTap: _onItemTap,
                    selectedItems: _selectedItems,
                    onItemSelected: (item, val) {
                      setState(() {
                        if (val == true) {
                          _selectedItems.add(item);
                        } else {
                          _selectedItems.remove(item);
                        }
                      });
                    },
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
                    selectedItems: _selectedItems,
                    onSelectAll: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedItems.addAll(items);
                        } else {
                          _selectedItems.removeAll(items);
                        }
                      });
                    },
                    onItemSelected: (item, val) {
                      setState(() {
                        if (val == true) {
                          _selectedItems.add(item);
                        } else {
                          _selectedItems.remove(item);
                        }
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
      // UploadOverlay is shown on demand via the transfer list button
    );
  }

  void _handleAction(String action, FileItem item) {
    if (action == 'rename') _handleRename(item);
    if (action == 'move') _handleMove(item);
    if (action == 'delete') _handleDelete(item);
    if (action == 'attach') _handleAttachToAi(item);
    if (action == 'download') _handleDownload(item);
  }

  Future<void> _handleDownload(FileItem item) async {
    final l10n = AppLocalizations.of(context)!;
    if (item.isDir) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.folderDownloadNotSupported)),
        );
      }
      return;
    }
    final downloadUrl = '${api.baseUrl}/api/files/download?path=${Uri.encodeComponent(item.path)}';
    final uri = Uri.parse(downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.downloadFailedMessage(item.name))),
        );
      }
    }
  }

  void _onItemTap(FileItem item) async {
    if (item.isDir) {
      setState(() => pathStack.add(pathStack.last.isEmpty ? item.name : "${pathStack.last}/${item.name}"));
      _refresh();
    } else {
      final ext = item.name.toLowerCase();
      final downloadUrl = '${api.baseUrl}/api/files/download?path=${Uri.encodeComponent(item.path)}';

      if (ext.endsWith('.pdf') || ext.endsWith('.docx')) {
        // Show a loading indicator immediately
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        // A small delay to ensure the dialog is rendered before navigation
        // and to give a visual cue of "loading" while the viewer prepares.
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        Navigator.pop(context); // Dismiss loading dialog

        if (ext.endsWith('.pdf')) {
          final navigateTo = await Navigator.push<String>(
            context,
            MaterialPageRoute(
              builder: (context) => PdfViewerPage(
                url: downloadUrl,
                title: item.name,
                fileItem: item,
                onActionSelected: _handleAction,
              ),
            ),
          );
          if (!mounted) return;
          api.invalidateFileListCache();
          if (navigateTo != null) {
            final parts = navigateTo.split('/');
            setState(() {
              pathStack = [''];
              for (final part in parts) {
                if (part.isNotEmpty) {
                  pathStack.add(pathStack.last.isEmpty ? part : '${pathStack.last}/$part');
                }
              }
            });
          }
          _refresh(forceRefresh: true);
        } else if (ext.endsWith('.docx')) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DocxViewerPage(url: downloadUrl, title: item.name),
            ),
          );
        }
      } else if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].any((suffix) => ext.endsWith(suffix))) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageViewerPage(
              thumbnailUrl: item.thumbnailUrl,
              originalUrl: downloadUrl,
              title: item.name,
              fileSize: item.size,
              fileItem: item,
              onActionSelected: _handleAction,
            ),
          ),
        );
      }
    }
  }
}