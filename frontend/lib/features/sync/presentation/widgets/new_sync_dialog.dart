import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/models/sync_pair.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/features/file_browser/presentation/widgets/folder_picker_dialog.dart';

class NewSyncDialog extends StatefulWidget {
  final void Function(SyncPair config) onCreated;
  final SyncPair? config;

  const NewSyncDialog({super.key, required this.onCreated, this.config});

  @override
  State<NewSyncDialog> createState() => _NewSyncDialogState();
}

class _NewSyncDialogState extends State<NewSyncDialog> {
  final _log = Logger('NewSyncDialog');
  final ApiService api = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _sourceController = TextEditingController();
  final _targetController = TextEditingController();
  final _intervalController = TextEditingController(text: '0');
  bool _creating = false;
  bool _deleteAfterSync = false;
  String _syncPolicy = 'interval';
  String _syncTime = '';
  TimeOfDay? _selectedTime;

  bool get _isEditing => widget.config != null;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    if (c != null) {
      _nameController.text = c.name;
      _sourceController.text = c.sourcePath;
      _targetController.text = c.targetPath;
      _intervalController.text = c.syncIntervalSecs.toString();
      _deleteAfterSync = c.deleteAfterSync;
      _syncPolicy = c.syncPolicy;
      _syncTime = c.syncTime;
      if (_syncTime.isNotEmpty) {
        final parts = _syncTime.split(':');
        if (parts.length == 3) {
          _selectedTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 0,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sourceController.dispose();
    _targetController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _pickLocalFolder() async {
    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory != null && mounted) {
      setState(() => _sourceController.text = selectedDirectory);
    }
  }

  Future<void> _pickRemoteFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final targetDir = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(
        currentPath: '',
        title: l10n.syncSelectTargetFolder,
        actionLabel: l10n.createButton,
        actionIcon: Icons.folder,
      ),
    );
    if (targetDir != null && mounted) {
      setState(() => _targetController.text = targetDir);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (time != null && mounted) {
      setState(() {
        _selectedTime = time;
        _syncTime = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _creating = true);
    try {
      final config = SyncPair(
        id: _isEditing ? widget.config!.id : 0,
        name: _nameController.text.trim(),
        sourcePath: _sourceController.text.trim(),
        targetPath: _targetController.text.trim(),
        syncIntervalSecs: int.tryParse(_intervalController.text) ?? 0,
        syncPolicy: _syncPolicy,
        syncTime: _syncTime,
        deleteAfterSync: _deleteAfterSync,
      );
      final saved = _isEditing
          ? await api.sync.updateConfig(config)
          : await api.sync.createConfig(config);
      widget.onCreated(saved);
    } catch (e) {
      _log.severe('Failed to save sync config: $e');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? l10n.syncUpdateFailed(e.toString())
              : l10n.syncCreateFailed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.sync, color: cs.primary),
                const SizedBox(width: 12),
                Text(
                  _isEditing ? l10n.syncEditConfig : l10n.syncNewConfig,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: l10n.syncNameLabel,
                        hintText: l10n.syncNameHint,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? l10n.syncNameRequired : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _sourceController,
                      readOnly: _isEditing,
                      decoration: InputDecoration(
                        labelText: l10n.syncSourceLabel,
                        hintText: l10n.syncSourceHint,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.folder_open),
                          tooltip: l10n.syncBrowseLocalFolder,
                          onPressed: _isEditing ? null : _pickLocalFolder,
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? l10n.syncSourceRequired : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _targetController,
                      readOnly: _isEditing,
                      decoration: InputDecoration(
                        labelText: l10n.syncTargetLabel,
                        hintText: l10n.syncTargetHint,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.cloud),
                          tooltip: l10n.syncBrowseNasFolder,
                          onPressed: _isEditing ? null : _pickRemoteFolder,
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? l10n.syncTargetRequired : null,
                    ),
                    const SizedBox(height: 16),

                    // ── Sync policy selector ──
                    Text(l10n.syncPolicyLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'interval', label: Text(l10n.syncTypeInterval)),
                        ButtonSegment(value: 'daily', label: Text(l10n.syncTypeDaily)),
                        ButtonSegment(value: 'watch', label: Text(l10n.syncTypeWatch)),
                      ],
                      selected: {_syncPolicy},
                      onSelectionChanged: (v) => setState(() => _syncPolicy = v.first),
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: 16),

                    // ── Interval field ──
                    if (_syncPolicy == 'interval')
                      TextFormField(
                        controller: _intervalController,
                        decoration: InputDecoration(
                          labelText: l10n.syncIntervalLabel,
                          hintText: l10n.syncIntervalHint,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),

                    // ── Daily time picker ──
                    if (_syncPolicy == 'daily')
                      InkWell(
                        onTap: _pickTime,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: l10n.syncDailyTimeLabel,
                            border: const OutlineInputBorder(),
                            suffixIcon: const Icon(Icons.access_time),
                          ),
                          child: Text(
                            _selectedTime != null
                                ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
                                : '',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ),

                    // ── Watch note ──
                    if (_syncPolicy == 'watch')
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.visibility, size: 20, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.syncWatchNote,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _deleteAfterSync,
                      onChanged: (v) => setState(() => _deleteAfterSync = v ?? false),
                      title: Text(l10n.syncDeleteAfterSyncLabel),
                      subtitle: Text(l10n.syncDeleteAfterSyncHint),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: FilledButton.icon(
              onPressed: _creating ? null : _save,
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_creating
                  ? l10n.saving
                  : (_isEditing ? l10n.saveButton : l10n.createButton)),
            ),
          ),
        ],
      ),
    );
  }
}
