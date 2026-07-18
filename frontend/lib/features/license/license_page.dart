import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:ainas_frontend/services/lic_service.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';

class LicActivationPage extends StatefulWidget {
  final VoidCallback? onLicensed;
  const LicActivationPage({super.key, this.onLicensed});

  @override
  State<LicActivationPage> createState() => _LicActivationPageState();
}

class _LicActivationPageState extends State<LicActivationPage> {
  final _lic = LicService();
  final _pasteController = TextEditingController();
  bool _loading = true;
  bool _importing = false;
  bool _licensed = false;
  LicenseStatus? _licenseStatus;
  String? _licensePath;
  Map<String, String> _hardwareInfo = {};
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    // Run license status, path, and hardware info in parallel
    final results = await Future.wait([
      _lic.licenseStatus(),
      _lic.licenseFilePath(),
      Future.value(_lic.hardwareInfo()),
    ]);
    if (!mounted) return;
    final status = results[0] as LicenseStatus;
    final path = results[1] as String;
    final info = results[2] as Map<String, String>;
    setState(() {
      _loading = false;
      _licensed = status.valid;
      _licenseStatus = status;
      _licensePath = path;
      _hardwareInfo = info;
    });
    if (status.valid && widget.onLicensed != null) {
      widget.onLicensed!();
    }
  }

  void _copyHardwareInfo() {
    final buf = StringBuffer();
    if (_hardwareInfo['cpu_serial']!.isNotEmpty) {
      buf.writeln('CPU Serial: ${_hardwareInfo['cpu_serial']}');
    }
    if (_hardwareInfo['motherboard_serial']!.isNotEmpty) {
      buf.writeln('Motherboard Serial: ${_hardwareInfo['motherboard_serial']}');
    }
    if (_hardwareInfo['disk_serial']!.isNotEmpty) {
      buf.writeln('Disk Serial: ${_hardwareInfo['disk_serial']}');
    }
    if (_hardwareInfo['device_fingerprint']!.isNotEmpty) {
      buf.writeln('Device Fingerprint: ${_hardwareInfo['device_fingerprint']}');
    }
    Clipboard.setData(ClipboardData(text: buf.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.licenseCopied)),
    );
  }

  Future<void> _pickAndImportFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    String content;
    if (file.path != null) {
      content = await File(file.path!).readAsString();
    } else if (file.bytes != null) {
      content = String.fromCharCodes(file.bytes!);
    } else {
      return;
    }
    await _doImport(content);
  }

  Future<void> _doImport(String content) async {
    if (content.trim().isEmpty) return;
    setState(() {
      _importing = true;
      _errorText = null;
    });
    final ok = await _lic.importLicense(content);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.licenseImportSuccess)),
      );
      await _check();
    } else {
      setState(() {
        _importing = false;
        _errorText = AppLocalizations.of(context)!.licenseImportFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.licenseTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_licensed) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.licenseTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: l10n.licenseImportTooltip,
              onPressed: _pickAndImportFile,
            ),
          ],
        ),
        body: _buildLicensedList(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.licenseTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              l10n.licenseNotLicensed,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.licenseSendToDeveloper,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildHardwareCard(l10n, theme),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _copyHardwareInfo,
              icon: const Icon(Icons.copy),
              label: Text(l10n.licenseCopyHardwareInfo),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _pickAndImportFile,
              icon: const Icon(Icons.file_open),
              label: Text(l10n.licenseImportFile),
            ),
            const SizedBox(height: 16),
            Text(l10n.licensePasteContent, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: _pasteController,
              maxLines: 5,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '-----BEGIN LICENSE-----\n...',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _importing
                  ? null
                  : () => _doImport(_pasteController.text),
              child: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.licenseImportButton),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorText!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLicensedList() {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final dateFormat = DateFormat('yyyy-MM-dd');
    final isExpiringSoon = _licenseStatus != null &&
        _licenseStatus!.daysRemaining >= 0 &&
        _licenseStatus!.daysRemaining <= 30;

    final permissions = _licenseStatus?.data?['permissions'];
    final features = <String>[];
    if (permissions is List) {
      for (final p in permissions) {
        features.add(p.toString());
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHardwareCard(l10n, theme),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isExpiringSoon
                          ? Icons.warning_amber_rounded
                          : Icons.verified,
                      color: isExpiringSoon ? Colors.orange : Colors.green,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.licenseLicensed,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                if (_licenseStatus?.issuedDate != null)
                  _detailRow(
                    l10n.licenseIssued,
                    dateFormat.format(_licenseStatus!.issuedDate!),
                  ),
                if (_licenseStatus?.expiresDate != null)
                  _detailRow(
                    l10n.licenseExpires,
                    dateFormat.format(_licenseStatus!.expiresDate!),
                  ),
                _detailRow(l10n.licenseDaysRemaining, '${_licenseStatus!.daysRemaining}'),
                if (_licensePath != null) _detailRow(l10n.licenseFile, _licensePath!),
                ...[
                  const Divider(),
                  Text(l10n.licensePermissions,
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ..._buildFeatureList(features, theme, l10n),
                ],
                if (isExpiringSoon) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.licenseExpiresSoon,
                      style: TextStyle(color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _confirmDeleteLicense,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.licenseDelete),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _pickAndImportFile,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.licenseUpdateRenew),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmDeleteLicense() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.licenseDeleteTitle),
        content: Text(l10n.licenseDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.licenseCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.licenseDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _lic.deleteLicense();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.licenseDeleteSuccess)),
      );
      await _check();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.licenseDeleteFailed)),
      );
    }
  }

  List<Widget> _buildFeatureList(List<String> permissions, ThemeData theme, AppLocalizations l10n) {
    final hasAll = permissions.contains('all');
    final granted = <String>{};
    for (final p in permissions) {
      granted.add(p);
    }
    final items = <Widget>[];

    void addFeature(String name, IconData icon, String label) {
      if (name == 'all') return;
      final isGranted = hasAll || granted.contains(name);
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                isGranted ? Icons.check_circle : Icons.lock_outline,
                color: isGranted ? Colors.green : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 10),
              Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 14)),
              const Spacer(),
              Text(
                isGranted ? l10n.licensePermissionGranted : l10n.licensePermissionDenied,
                style: TextStyle(
                  fontSize: 12,
                  color: isGranted ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    addFeature('all',       Icons.all_inclusive,  l10n.licenseFeatureAll);
    addFeature('ai',        Icons.auto_awesome,   l10n.licenseFeatureAi);
    addFeature('multiuser', Icons.people,         l10n.licenseFeatureMultiuser);
    addFeature('sync',      Icons.sync,           l10n.licenseFeatureSync);
    addFeature('storage',   Icons.storage,        l10n.licenseFeatureStorage);

    if (hasAll && permissions.length > 1) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.licenseAdditionalPermissions(permissions.where((p) => p != 'all').join(', ')),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),
      );
    }
    return items;
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareCard(AppLocalizations l10n, ThemeData theme) {
    final entries = [
      if (_hardwareInfo['cpu_serial']!.isNotEmpty)
        (_hardwareInfo['cpu_serial']!, l10n.licenseCpuSerial),
      if (_hardwareInfo['motherboard_serial']!.isNotEmpty)
        (_hardwareInfo['motherboard_serial']!, l10n.licenseMotherboardSerial),
      if (_hardwareInfo['disk_serial']!.isNotEmpty)
        (_hardwareInfo['disk_serial']!, l10n.licenseDiskSerial),
      if (_hardwareInfo['device_fingerprint']!.isNotEmpty)
        (_hardwareInfo['device_fingerprint']!, l10n.licenseDeviceFingerprint),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.precision_manufacturing_outlined, size: 24,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Hardware Info',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: l10n.licenseCopyHardwareInfo,
                  onPressed: _copyHardwareInfo,
                ),
              ],
            ),
            const Divider(),
            for (final (value, label) in entries) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13,
                            color: Colors.grey)),
                    const SizedBox(height: 2),
                    SelectableText(value,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 14,
                            height: 1.4)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
