import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
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
    // Run hardware info and license check in parallel
    final results = await Future.wait([
      _lic.isLicensed(),
      Future.value(_lic.hardwareInfo()),
    ]);
    if (!mounted) return;
    final licensed = results[0] as bool;
    final info = results[1] as Map<String, String>;
    setState(() {
      _loading = false;
      _licensed = licensed;
      _hardwareInfo = info;
    });
    if (licensed && widget.onLicensed != null) {
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
        appBar: AppBar(title: Text(l10n.licenseTitle)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified, size: 72, color: Colors.green),
              const SizedBox(height: 16),
              Text(l10n.licenseLicensed, style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
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
            if (_hardwareInfo['cpu_serial']!.isNotEmpty) ...[
              _infoRow(l10n.licenseCpuSerial, _hardwareInfo['cpu_serial']!),
              const SizedBox(height: 8),
            ],
            if (_hardwareInfo['motherboard_serial']!.isNotEmpty) ...[
              _infoRow(l10n.licenseMotherboardSerial, _hardwareInfo['motherboard_serial']!),
              const SizedBox(height: 8),
            ],
            if (_hardwareInfo['disk_serial']!.isNotEmpty) ...[
              _infoRow(l10n.licenseDiskSerial, _hardwareInfo['disk_serial']!),
              const SizedBox(height: 8),
            ],
            if (_hardwareInfo['device_fingerprint']!.isNotEmpty) ...[
              _infoRow(l10n.licenseDeviceFingerprint, _hardwareInfo['device_fingerprint']!),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
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

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
      ],
    );
  }
}
