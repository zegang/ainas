import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ainas_frontend/l10n/app_localizations.dart';

class LogViewerPage extends StatefulWidget {
  final String logFileName;
  const LogViewerPage({super.key, this.logFileName = 'ainas_frontend.log'});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  String? _logContent;
  String? _error;
  bool _loading = true;
  bool _truncated = false;
  String _logFilePath = '';
  static const int _maxChars = 500 * 1024;

  double _fontSize = 11;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final List<int> _matchStarts = [];
  int _currentMatchIndex = -1;
  final ScrollController _scrollController = ScrollController();

  static const double _minFontSize = 8;
  static const double _maxFontSize = 32;
  static const double _fontStep = 2;

  String get _logFileName => widget.logFileName;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadLog);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLog() async {
    if (kIsWeb) {
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _logFilePath = '$_logFileName (${l10n.logWebUnavailable})';
        _error = l10n.logWebUnavailable;
        _loading = false;
      });
      return;
    }

    try {
      final file = File(_logFileName);
      final l10n = AppLocalizations.of(context)!;
      _logFilePath = file.absolute.path;
      if (!await file.exists()) {
        setState(() {
          _error = l10n.logFileNotFound;
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
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _error = l10n.logReadFailed(e.toString());
        _loading = false;
      });
    }
  }

  void _updateMatches() {
    _matchStarts.clear();
    _currentMatchIndex = -1;
    if (_logContent == null || _searchQuery.isEmpty) return;
    final text = _logContent!;
    final query = _searchQuery.toLowerCase();
    final lower = text.toLowerCase();
    int start = 0;
    while (true) {
      final idx = lower.indexOf(query, start);
      if (idx == -1) break;
      _matchStarts.add(idx);
      start = idx + query.length;
    }
    if (_matchStarts.isNotEmpty) _currentMatchIndex = 0;
  }

  void _goToMatch(int direction) {
    if (_matchStarts.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + direction + _matchStarts.length) % _matchStarts.length;
    });
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
      _matchStarts.clear();
      _currentMatchIndex = -1;
    });
    _loadLog();
  }

  List<TextSpan> _buildSpans() {
    if (_logContent == null) return [];
    if (_searchQuery.isEmpty || _matchStarts.isEmpty) {
      return [TextSpan(text: _logContent)];
    }

    final spans = <TextSpan>[];
    final text = _logContent!;
    final queryLen = _searchQuery.length;
    int lastEnd = 0;

    for (int i = 0; i < _matchStarts.length; i++) {
      final start = _matchStarts[i];
      if (start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, start)));
      }
      final isCurrent = i == _currentMatchIndex;
      spans.add(TextSpan(
        text: text.substring(start, start + queryLen),
        style: TextStyle(
          backgroundColor: isCurrent ? Colors.orange : Colors.yellowAccent,
          color: isCurrent ? Colors.white : Colors.black87,
          fontWeight: FontWeight.bold,
        ),
      ));
      lastEnd = start + queryLen;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.logViewerTitle),
        actions: [
          if (_logContent != null) ...[
            if (!_isSearching)
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: l10n.searchHint,
                onPressed: () => setState(() => _isSearching = true),
              ),
            if (_isSearching)
              IconButton(
                icon: const Icon(Icons.search_off),
                tooltip: l10n.cancelButton,
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                    _matchStarts.clear();
                    _currentMatchIndex = -1;
                  });
                },
              ),
            IconButton(
              icon: const Icon(Icons.text_decrease),
              tooltip: l10n.zoomOut,
              onPressed: _fontSize > _minFontSize
                  ? () => setState(() => _fontSize = (_fontSize - _fontStep).clamp(_minFontSize, _maxFontSize))
                  : null,
            ),
            Text(
              '${_fontSize.round()}',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimary.withOpacity(0.7)),
            ),
            IconButton(
              icon: const Icon(Icons.text_increase),
              tooltip: l10n.zoomIn,
              onPressed: _fontSize < _maxFontSize
                  ? () => setState(() => _fontSize = (_fontSize + _fontStep).clamp(_minFontSize, _maxFontSize))
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: l10n.copyText,
              onPressed: _copyLog,
            ),
          ],
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
        if (_logFilePath.isNotEmpty)
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.folder_open, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _logFilePath,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        if (_isSearching)
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: l10n.logSearchHint,
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _updateMatches();
                      });
                    },
                  ),
                ),
                if (_searchQuery.isNotEmpty) ...[
                  Text(
                    _matchStarts.isEmpty
                        ? '0/0'
                        : '${_currentMatchIndex + 1}/${_matchStarts.length}',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: _matchStarts.isNotEmpty ? () => _goToMatch(-1) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: _matchStarts.isNotEmpty ? () => _goToMatch(1) : null,
                  ),
                ],
              ],
            ),
          ),
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
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            child: SelectableText.rich(
              TextSpan(
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: _fontSize,
                  height: 1.4,
                ),
                children: _buildSpans(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
