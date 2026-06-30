import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ainas_frontend/l10n/app_localizations.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  String? _logContent;
  String? _error;
  bool _loading = true;
  bool _truncated = false;
  static const int _maxChars = 500 * 1024;
  static const String _logFileName = 'ainas_frontend.log';

  @override
  void initState() {
    super.initState();
    _loadLog();
  }

  Future<void> _loadLog() async {
    if (kIsWeb) {
      setState(() {
        _error = 'Log file is not available on web. Logs are printed to the browser console instead.';
        _loading = false;
      });
      return;
    }

    try {
      final file = File(_logFileName);
      if (!await file.exists()) {
        setState(() {
          _error = 'Log file not found. Please start using the app first.';
          _loading = false;
        });
        return;
      }

      final length = await file.length();
      if (length > _maxChars) {
        final raf = await file.open(mode: FileMode.read);
        await raf.setPosition(length - _maxChars);
        final bytes = await raf.read(_maxChars);
        await raf.close();
        final raw = String.fromCharCodes(bytes);
        final firstNewline = raw.indexOf('\n');
        final content = firstNewline > 0 ? raw.substring(firstNewline + 1) : raw;
        setState(() {
          _logContent = content;
          _truncated = true;
          _loading = false;
        });
      } else {
        final content = await file.readAsString();
        setState(() {
          _logContent = content;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to read log file: $e';
        _loading = false;
      });
    }
  }

  Future<void> _copyLog() async {
    if (_logContent == null) return;
    await Clipboard.setData(ClipboardData(text: _logContent!));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.copiedToClipboard)),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _logContent = null;
      _error = null;
      _truncated = false;
    });
    _loadLog();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.logViewerTitle),
        actions: [
          if (_logContent != null)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: l10n.copyText,
              onPressed: _copyLog,
            ),
          if (kIsWeb && _error != null)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: l10n.copyText,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _error!));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.copiedToClipboard)),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refreshTooltip,
            onPressed: _refresh,
          ),
        ],
      ),
      body: _buildBody(l10n, theme),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retryAction),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_truncated)
          Container(
            width: double.infinity,
            color: theme.colorScheme.tertiaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 18, color: theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.logTruncated,
                    style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: SelectableText(
            _logContent!,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
