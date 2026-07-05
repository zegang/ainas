import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/shared/models/sync_pair.dart';
import 'new_sync_dialog.dart';

class _FileStatus {
  final String path;
  final int size;
  final String status;

  _FileStatus({required this.path, required this.size, required this.status});
}

class SyncDetailsPage extends StatefulWidget {
  final SyncPair config;

  const SyncDetailsPage({super.key, required this.config});

  @override
  State<SyncDetailsPage> createState() => _SyncDetailsPageState();
}

class _SyncDetailsPageState extends State<SyncDetailsPage> {
  final _log = Logger('SyncDetailsPage');
  final ApiService api = ApiService();
  late SyncPair _config;
  int _targetFileCount = 0;
  int _syncedFileCount = 0;
  int _pendingCount = 0;
  bool _loadingStats = true;
  List<_FileStatus> _files = [];
  List<_FileStatus> _serverFiles = [];
  Timer? _scanTimer;
  DateTime? _scanStart;
  int _elapsedSeconds = 0;
  int _selectedTab = 0;
  Timer? _countdownTimer;
  String _countdownText = '';

  static const _tabLabels = ['source', 'synced', 'pending', 'target'];

  List<_FileStatus> get _filteredFiles {
    switch (_selectedTab) {
      case 0:
        return _files;
      case 1:
        return _files.where((f) => f.status == 'synced').toList();
      case 2:
        return _files.where((f) => f.status == 'pending').toList();
      case 3:
        return _serverFiles;
      default:
        return _files;
    }
  }

  int get _filteredCount {
    switch (_selectedTab) {
      case 0:
        return _files.length;
      case 1:
        return _syncedFileCount;
      case 2:
        return _pendingCount;
      case 3:
        return _targetFileCount;
      default:
        return _files.length;
    }
  }

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCountdown());
    _scanAndCheck();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _scanAndCheck() async {
    setState(() => _loadingStats = true);
    _files = [];
    _serverFiles = [];
    _pendingCount = 0;
    _syncedFileCount = 0;
    _elapsedSeconds = 0;
    _scanStart = DateTime.now();
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSeconds = DateTime.now().difference(_scanStart!).inSeconds);
      }
    });

    try {
      await _loadServerStats();
      final dir = Directory(_config.sourcePath);
      if (!await dir.exists()) {
        if (mounted) setState(() => _loadingStats = false);
        _scanTimer?.cancel();
        return;
      }

      final localFiles = <Map<String, dynamic>>[];
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final stat = await entity.stat();
          localFiles.add({
            'path': entity.path.substring(dir.path.length + 1),
            'size': stat.size,
            'modified_at': stat.modified.toIso8601String(),
          });
        }
      }

      if (!mounted) {
        _scanTimer?.cancel();
        return;
      }

      setState(() {
        _sourceFileCount = localFiles.length;
      });

      Map<String, dynamic> diffResult;
      try {
        diffResult = await api.sync.diffManifest(_config.id, localFiles);
      } catch (e) {
        _log.warning('diff failed, marking all as pending: $e');
        for (final f in localFiles) {
          _files.add(_FileStatus(
            path: f['path'] as String,
            size: f['size'] as int,
            status: 'pending',
          ));
        }
        if (mounted) setState(() {
          _pendingCount = _files.length;
          _loadingStats = false;
        });
        _scanTimer?.cancel();
        return;
      }

      final toUploadSet = <String>{};
      for (final f in (diffResult['files_to_upload'] as List?) ?? []) {
        toUploadSet.add(f['path'] as String);
      }

      for (final f in localFiles) {
        final path = f['path'] as String;
        final status = toUploadSet.contains(path) ? 'pending' : 'synced';
        _files.add(_FileStatus(
          path: path,
          size: f['size'] as int,
          status: status,
        ));
      }

      _serverFiles.clear();
      for (final f in (diffResult['server_files'] as List?) ?? []) {
        _serverFiles.add(_FileStatus(
          path: f['path'] as String,
          size: (f['size'] as num?)?.toInt() ?? 0,
          status: 'synced',
        ));
      }

      if (mounted) setState(() {
        _pendingCount = _files.where((f) => f.status == 'pending').length;
        _syncedFileCount = _files.where((f) => f.status == 'synced').length;
        _loadingStats = false;
      });
    } catch (e) {
      _log.warning('Scan failed: $e');
      if (mounted) setState(() => _loadingStats = false);
    }
    _scanTimer?.cancel();
  }

  int? _sourceFileCount;

  Future<void> _loadServerStats() async {
    try {
      final stats = await api.sync.getStats(_config.id);
      if (mounted) {
        setState(() {
          _targetFileCount = (stats['target_file_count'] as int?) ?? 0;
        });
      }
    } catch (e) {
      _log.warning('Failed to load server stats: $e');
    }
  }

  Future<void> _edit() async {
    final result = await showModalBottomSheet<SyncPair>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: NewSyncDialog(
            config: _config,
            onCreated: (updated) => Navigator.pop(context, updated),
          ),
        ),
      ),
    );
    if (result != null) {
      setState(() => _config = result);
    }
  }

  void _showMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isMobile = Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_upload),
                title: Text(l10n.startSync),
                onTap: () {
                  Navigator.pop(ctx);
                  _startSync();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download),
                title: Text(l10n.pullToLocal),
                onTap: () {
                  Navigator.pop(ctx);
                  _pullToLocal();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.editButton),
                onTap: () {
                  Navigator.pop(ctx);
                  _edit();
                },
              ),
            ],
          ),
        ),
      );
    } else {
      final renderBox = context.findRenderObject() as RenderBox;
      final offset = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          offset & size,
          Offset.zero & MediaQuery.of(context).size,
        ),
        items: [
          PopupMenuItem(
            value: 'sync',
            child: ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: Text(l10n.startSync),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'pull',
            child: ListTile(
              leading: const Icon(Icons.cloud_download),
              title: Text(l10n.pullToLocal),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.editButton),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ).then((value) {
        if (value == 'sync') _startSync();
        if (value == 'pull') _pullToLocal();
        if (value == 'edit') _edit();
      });
    }
  }

  Future<void> _startSync() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _loadingStats = true);
    try {
      final dir = Directory(_config.sourcePath);
      if (!await dir.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.syncSourceNotFound), backgroundColor: Colors.red),
        );
        setState(() => _loadingStats = false);
        return;
      }

      final files = <Map<String, dynamic>>[];
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final stat = await entity.stat();
          files.add({
            'path': entity.path.substring(dir.path.length + 1),
            'size': stat.size,
            'modified_at': stat.modified.toIso8601String(),
          });
        }
      }

      if (files.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.syncSourceEmpty)),
        );
        setState(() => _loadingStats = false);
        return;
      }

      final diffResult = await api.sync.diffManifest(_config.id, files);
      final toUpload = (diffResult['files_to_upload'] as List?) ?? [];

      if (toUpload.isEmpty) {
        if (_config.deleteAfterSync) {
          if (await _deleteSourceContents(dir) && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.syncSourceFilesRemoved), backgroundColor: Colors.green),
            );
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.syncAlreadyUpToDate), backgroundColor: Colors.green),
        );
        setState(() => _loadingStats = false);
        return;
      }

      for (int i = 0; i < toUpload.length; i++) {
        final f = toUpload[i] as Map<String, dynamic>;
        final path = f['path'] as String;
        final localPath = '${dir.path}/$path';
        final file = File(localPath);
        if (!await file.exists()) continue;
        await api.sync.uploadFile(_config.id, localPath, path);
      }

      final uploadedPaths = toUpload.map((f) => f['path'] as String).toList();
      await api.sync.commitSync(_config.id, uploadedPaths);

      if (_config.deleteAfterSync) {
        if (await _deleteSourceContents(dir) && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.syncSourceFilesRemoved), backgroundColor: Colors.green),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.syncCompleted), backgroundColor: Colors.green),
      );
    } catch (e) {
      _log.severe('Sync failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.syncFailed), backgroundColor: Colors.red),
      );
    }
    setState(() => _loadingStats = false);
    _scanAndCheck();
  }

  Future<bool> _deleteSourceContents(Directory dir) async {
    try {
      bool anyDeleted = false;
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        anyDeleted = true;
        if (entity is Directory) {
          await entity.delete(recursive: true);
        } else {
          await entity.delete();
        }
      }
      return anyDeleted;
    } catch (e) {
      _log.warning('Failed to clear source folder: $e');
      return false;
    }
  }

  Future<void> _pullToLocal() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _loadingStats = true);
    try {
      final dir = Directory(_config.sourcePath);
      if (!await dir.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.syncSourceNotFound), backgroundColor: Colors.red),
        );
        setState(() => _loadingStats = false);
        return;
      }

      final localFiles = <String, int>{};
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final stat = await entity.stat();
          localFiles[entity.path.substring(dir.path.length + 1)] = stat.size;
        }
      }

      final diffResult = await api.sync.diffManifest(_config.id, []);
      final serverFiles = (diffResult['server_files'] as List?) ?? [];

      final toDownload = <Map<String, dynamic>>[];
      for (final f in serverFiles) {
        final path = f['path'] as String;
        final size = (f['size'] as num?)?.toInt() ?? 0;
        if (!localFiles.containsKey(path) || localFiles[path] != size) {
          toDownload.add(f);
        }
      }

      if (toDownload.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.syncAlreadyUpToDate), backgroundColor: Colors.green),
        );
        setState(() => _loadingStats = false);
        return;
      }

      for (final f in toDownload) {
        final path = f['path'] as String;
        final localPath = '${dir.path}/$path';
        await api.sync.downloadFile(_config.id, path, localPath);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.syncCompleted}: ${toDownload.length} files pulled'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _log.severe('Pull to local failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.syncFailed), backgroundColor: Colors.red),
      );
    }
    setState(() => _loadingStats = false);
    _scanAndCheck();
  }

  Future<void> _refresh() async {
    try {
      final config = await api.sync.getConfig(_config.id);
      setState(() => _config = config);
    } catch (e) {
      _log.severe('Failed to refresh config: $e');
    }
    await _scanAndCheck();
  }

  String _formatCount(int? count) {
    if (count == null) return '...';
    if (count == -1) return '?';
    return count.toString();
  }

  String _formatElapsed(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final c = _config;

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          Builder(
            builder: (ctx) {
              return IconButton(
                icon: const Icon(Icons.more_vert),
                tooltip: l10n.moreOptions,
                onPressed: () => _showMenu(ctx),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionHeader(l10n.syncConfigInfo),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(l10n.syncNameLabel, c.name),
                    const Divider(),
                    _infoRow(l10n.syncSourceLabel, c.sourcePath),
                    const Divider(),
                    _infoRow(l10n.syncTargetLabel, c.targetPath),
                    const Divider(),
                    _infoRow(
                      c.syncPolicy == 'daily' ? l10n.syncTypeDaily
                          : c.syncPolicy == 'watch' ? l10n.syncTypeWatch
                          : l10n.syncTypeInterval,
                      c.syncPolicy == 'daily' && c.syncTime.isNotEmpty ? c.syncTime
                          : c.syncPolicy == 'interval' ? '${c.syncIntervalSecs}s'
                          : '-',
                    ),
                    if (c.syncPolicy == 'daily' && _countdownText.isNotEmpty) ...[
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 140,
                              child: Text(l10n.syncNextSyncIn,
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ),
                            Expanded(child: Text(_countdownText)),
                          ],
                        ),
                      ),
                    ],
                    const Divider(),
                    _infoRow(l10n.enabledLabel, c.enabled ? l10n.yesLabel : l10n.noLabel),
                    if (c.lastSyncedAt != null && c.lastSyncedAt!.isNotEmpty) ...[
                      const Divider(),
                      _infoRow(l10n.syncLastSyncedTime, _formatLastSync(c.lastSyncedAt!)),
                    ],
                    const Divider(),
                    _infoRow(l10n.syncDeleteAfterSyncLabel, c.deleteAfterSync ? l10n.yesLabel : l10n.noLabel),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _sectionHeader(l10n.syncStats),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _loadingStats
                    ? Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 12),
                              Text(_formatElapsed(_elapsedSeconds)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _sourceFileCount != null
                                ? '$_sourceFileCount ${l10n.syncFilesFound}'
                                : l10n.syncScanning,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildTab(0, l10n.syncSourceCount, _formatCount(_sourceFileCount), Icons.folder_open, cs.primary)),
                              Container(width: 1, height: 48, color: cs.outlineVariant),
                              Expanded(child: _buildTab(1, l10n.syncSyncedCount, _formatCount(_syncedFileCount), Icons.check_circle, Colors.green)),
                              Container(width: 1, height: 48, color: cs.outlineVariant),
                              Expanded(child: _buildTab(2, l10n.syncPendingCount, _formatCount(_pendingCount), Icons.hourglass_empty, Colors.orange.shade700)),
                              Container(width: 1, height: 48, color: cs.outlineVariant),
                              Expanded(child: _buildTab(3, l10n.syncTargetCount, _formatCount(_targetFileCount), Icons.cloud, Colors.orange)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_filteredFiles.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.hourglass_empty,
                                        size: 36, color: cs.onSurfaceVariant.withOpacity(0.4)),
                                    const SizedBox(height: 8),
                                    Text(
                                      l10n.syncFileListEmpty,
                                      style: TextStyle(color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _filteredFiles.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final f = _filteredFiles[index];
                                final isSynced = f.status == 'synced';
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isSynced ? Icons.check_circle : Icons.hourglass_empty,
                                    color: isSynced ? Colors.green : Colors.orange.shade700,
                                    size: 20,
                                  ),
                                  title: Text(
                                    f.path,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(
                                    _formatFileSize(f.size),
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(int index, String label, String count, IconData icon, Color color) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? color : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : color.withOpacity(0.5), size: 22),
            const SizedBox(height: 4),
            Text(
              count,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected ? color : null,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  void _updateCountdown() {
    if (_config.syncPolicy != 'daily' || _config.syncTime.isEmpty) {
      _countdownText = '';
      return;
    }
    final now = DateTime.now();
    final parts = _config.syncTime.split(':');
    var target = DateTime(
      now.year, now.month, now.day,
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 0,
    );
    if (now.isAfter(target)) {
      target = target.add(const Duration(days: 1));
    }
    final remaining = target.difference(now);
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60);
    final s = remaining.inSeconds.remainder(60);
    _countdownText = '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    if (mounted) setState(() {});
  }

  String _formatLastSync(String utcStr) {
    try {
      var isoStr = utcStr;
      if (!isoStr.contains('T')) {
        isoStr = isoStr.replaceAll(' ', 'T');
      }
      if (!isoStr.endsWith('Z')) {
        isoStr += 'Z';
      }
      final dt = DateTime.parse(isoStr);
      final local = dt.toLocal();
      return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return utcStr;
    }
  }
}
