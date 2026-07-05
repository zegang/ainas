import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/shared/models/sync_pair.dart';
import 'new_sync_dialog.dart';
import 'sync_details_page.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _log = Logger('SyncPage');
  final ApiService api = ApiService();
  List<SyncPair> _configs = [];
  bool _loading = true;
  bool _loadError = false;
  int? _syncingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final configs = await api.sync.listConfigs();
      setState(() {
        _configs = configs;
        _loading = false;
      });
    } catch (e) {
      _log.severe('Failed to load sync configs: $e');
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  Future<void> _createNew() async {
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
          child: NewSyncDialog(onCreated: (config) {
            Navigator.pop(context, config);
          }),
        ),
      ),
    );
    if (result != null) {
      _load();
    }
  }

  Future<void> _toggle(SyncPair config) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await api.sync.toggleConfig(config.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.syncToggleFailed(e.toString())), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _trigger(SyncPair config) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _syncingId = config.id);
    try {
      final dir = Directory(config.sourcePath);
      if (!await dir.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.syncSourceNotFound), backgroundColor: Colors.red),
        );
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
        return;
      }

      final diffResult = await api.sync.diffManifest(config.id, files);
      final toUpload = (diffResult['files_to_upload'] as List?) ?? [];

      if (toUpload.isEmpty) {
        if (config.deleteAfterSync) {
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
        return;
      }

      for (int i = 0; i < toUpload.length; i++) {
        final f = toUpload[i] as Map<String, dynamic>;
        final path = f['path'] as String;
        final localPath = '${dir.path}/$path';
        final file = File(localPath);
        if (!await file.exists()) continue;
        await api.sync.uploadFile(config.id, localPath, path);
      }

      final uploadedPaths = toUpload.map((f) => f['path'] as String).toList();
      await api.sync.commitSync(config.id, uploadedPaths);

      if (config.deleteAfterSync) {
        if (await _deleteSourceContents(dir) && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.syncSourceFilesRemoved), backgroundColor: Colors.green),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.syncTriggered(toUpload.length)),
          backgroundColor: Colors.green,
        ),
      );
      _load();
    } catch (e) {
      _log.severe('Sync failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.syncTriggerFailed(e.toString())), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _syncingId = null);
    }
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
      if (anyDeleted) {
        _log.info('Cleared contents of source folder after sync');
      }
      return anyDeleted;
    } catch (e) {
      _log.warning('Failed to clear source folder: $e');
      return false;
    }
  }

  void _openDetails(SyncPair config) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SyncDetailsPage(config: config),
      ),
    ).then((_) => _load());
  }

  Future<void> _editConfig(SyncPair config) async {
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
            config: config,
            onCreated: (updated) => Navigator.pop(context, updated),
          ),
        ),
      ),
    );
    if (result != null) {
      _load();
    }
  }

  Future<void> _delete(SyncPair config) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.syncDeleteTitle),
        content: Text(l10n.syncDeleteConfirm(config.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancelButton)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteButton, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await api.sync.deleteConfig(config.id);
        _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.syncDeleteFailed), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.syncTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refreshTooltip,
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.syncNewConfig,
            onPressed: _createNew,
          ),
        ],
      ),
      body: _buildBody(l10n, cs),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sync_problem, size: 64, color: cs.error.withOpacity(0.5)),
              const SizedBox(height: 16),
              Text(l10n.syncLoadFailed, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retryConnection),
              ),
            ],
          ),
        ),
      );
    }
    if (_configs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sync, size: 80, color: cs.primary.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(l10n.syncEmpty, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l10n.syncEmptyHint, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _createNew,
              icon: const Icon(Icons.add),
              label: Text(l10n.syncNewConfig),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _configs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final config = _configs[index];
          return _SyncConfigCard(
            config: config,
            isSyncing: _syncingId == config.id,
            onToggle: () => _toggle(config),
            onTrigger: () => _trigger(config),
            onDelete: () => _delete(config),
            onEdit: () => _editConfig(config),
            onTap: () => _openDetails(config),
          );
        },
      ),
    );
  }
}

class _SyncConfigCard extends StatelessWidget {
  final SyncPair config;
  final bool isSyncing;
  final VoidCallback onToggle;
  final VoidCallback onTrigger;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onTap;

  const _SyncConfigCard({
    required this.config,
    required this.isSyncing,
    required this.onToggle,
    required this.onTrigger,
    required this.onDelete,
    required this.onEdit,
    required this.onTap,
  });

  static String formatLastSync(String utcStr) {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        config.enabled ? Icons.sync : Icons.sync_disabled,
                        color: config.enabled ? cs.primary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              config.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${config.sourcePath} → ${config.targetPath}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (config.lastSyncedAt != null && config.lastSyncedAt!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.syncLastSynced(_SyncConfigCard.formatLastSync(config.lastSyncedAt!)),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Switch(
                value: config.enabled,
                onChanged: (_) => onToggle(),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: l10n.editButton,
                onPressed: onEdit,
              ),
              IconButton(
                icon: isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                tooltip: l10n.startSync,
                onPressed: isSyncing ? null : onTrigger,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: l10n.deleteButton,
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
