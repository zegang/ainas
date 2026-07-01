import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/features/home/presentation/widgets/storage_dashboard_widget.dart';
import 'package:ainas_frontend/shared/utils/backend_process_manager.dart';

class StorageDesktopPage extends StatefulWidget {
  const StorageDesktopPage({super.key});

  @override
  State<StorageDesktopPage> createState() => _StorageDesktopPageState();
}

class _StorageDesktopPageState extends State<StorageDesktopPage> {
  static const String _storageRootPathKey = 'storage_root_path';
  static const String _backendBinaryPathKey = 'backend_binary_path';
  static const String _listenAddrKey = 'backend_listen_addr';
  static const String _listenPortKey = 'backend_listen_port';
  static const String _logLevelKey = 'backend_log_level';
  static const String _logFilePathKey = 'backend_log_file_path';
  static const String _daemonKey = 'backend_run_as_daemon';

  static const List<String> _logLevels = ['trace', 'debug', 'info', 'warn', 'error'];

  final ApiService _api = ApiService();
  late TextEditingController _rootPathController;
  late TextEditingController _binaryPathController;
  late TextEditingController _addrController;
  late TextEditingController _portController;
  late TextEditingController _logFileController;
  String _logLevel = 'info';
  bool _runAsDaemon = true;
  Map<String, dynamic>? _usageData;
  List<int> _pids = [];
  bool _loadingUsage = true;
  bool _loadingPids = true;
  bool _stoppingPid = false;
  bool _startingProcess = false;
  Timer? _logFileDebounce;
  Timer? _storageRootDebounce;
  bool _optionsExpanded = false;
  String? _processMessage;
  String? _activeCommandLine;

  @override
  void initState() {
    super.initState();
    _rootPathController = TextEditingController();
    _binaryPathController = TextEditingController();
    _addrController = TextEditingController();
    _portController = TextEditingController();
    _logFileController = TextEditingController();
    _loadPersistedValues();
    _loadPids();
  }

  String _defaultStorageRoot() {
    try {
      return '${File(Platform.resolvedExecutable).parent.path}/storage';
    } catch (_) {
      return 'storage';
    }
  }

  String _defaultBackendBinaryPath() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidate = '$exeDir/ainas-backend-cpp.exe';
      if (FileSystemEntity.isFileSync(candidate)) return candidate;
    } catch (_) {}
    return '';
  }

  String _defaultLogFilePath() {
    try {
      final executableDir = File(Platform.resolvedExecutable).parent.path;
      return path.join(executableDir, 'ainas_backend.log');
    } catch (_) {
      return 'ainas_backend.log';
    }
  }

  Future<void> _loadPersistedValues() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRoot = prefs.getString(_storageRootPathKey);
    final savedBinary = prefs.getString(_backendBinaryPathKey);
    _rootPathController.text = savedRoot ?? _defaultStorageRoot();
    _binaryPathController.text = savedBinary ?? _defaultBackendBinaryPath();

    final savedAddr = prefs.getString(_listenAddrKey);
    _addrController.text = savedAddr ?? '0.0.0.0';

    final savedPort = prefs.getString(_listenPortKey);
    _portController.text = savedPort ?? '9026';

    _logLevel = prefs.getString(_logLevelKey) ?? 'info';

    final savedLogFile = prefs.getString(_logFilePathKey);
    _logFileController.text = savedLogFile ?? _defaultLogFilePath();

    _runAsDaemon = prefs.getBool(_daemonKey) ?? true;

    // Persist defaults if loading for the first time
    await prefs.setString(_listenAddrKey, _addrController.text);
    await prefs.setString(_listenPortKey, _portController.text);
    await prefs.setString(_logLevelKey, _logLevel);
    await prefs.setBool(_daemonKey, _runAsDaemon);
  }

  Future<void> _persistAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageRootPathKey, _rootPathController.text);
    await prefs.setString(_backendBinaryPathKey, _binaryPathController.text);
    await prefs.setString(_listenAddrKey, _addrController.text);
    await prefs.setString(_listenPortKey, _portController.text);
    await prefs.setString(_logLevelKey, _logLevel);
    await prefs.setString(_logFilePathKey, _logFileController.text);
    await prefs.setBool(_daemonKey, _runAsDaemon);
  }

  Future<void> _persistRootPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageRootPathKey, path);
  }

  Future<void> _persistBinaryPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendBinaryPathKey, path);
  }

  Future<void> _loadUsage() async {
    setState(() => _loadingUsage = true);
    try {
      _usageData = await _api.getSystemUsage();
    } catch (_) {
      _usageData = null;
    }
    if (mounted) setState(() => _loadingUsage = false);
  }

  Future<void> _loadPids() async {
    setState(() => _loadingPids = true);
    try {
      _pids = await BackendProcessManager.listPids();
    } catch (_) {
      _pids = [];
    }
    if (_pids.isNotEmpty && _activeCommandLine == null) {
      _activeCommandLine = _reconstructCommandLine();
    }
    if (_pids.isEmpty) _activeCommandLine = null;
    if (mounted) {
      setState(() => _loadingPids = false);
      if (_pids.isNotEmpty && _usageData == null) {
        _fetchAndShowConfig();
      }
    }
  }

  Future<void> _handleStop(int pid) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.stop),
        content: Text(l10n.processStopConfirm(pid.toString())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.stop, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _stoppingPid = true;
      _processMessage = null;
    });
    final ok = await BackendProcessManager.stopProcess(pid);
    if (mounted) {
      if (ok) {
        _usageData = null;
        _activeCommandLine = null;
        // Poll until the process is actually gone (up to ~5 s)
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          final remaining = await BackendProcessManager.listPids();
          if (!remaining.contains(pid)) break;
        }
      }
      setState(() {
        _stoppingPid = false;
      });
      if (ok) {
        await _loadPids();
      } else {
        setState(() => _processMessage = l10n.failedToStopPid(pid.toString()));
      }
    }
  }

  Future<void> _handleStart() async {
    final binaryPath = _binaryPathController.text.trim();
    if (binaryPath.isEmpty) {
      setState(() => _processMessage = AppLocalizations.of(context)!.enterBinaryPathFirst);
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.start),
        content: Text(l10n.startBackendConfirm(binaryPath)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.start)),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _startingProcess = true;
      _processMessage = null;
    });
    await _persistBinaryPath(binaryPath);
    await _persistAll();

    final List<String> args = [];
    final addr = _addrController.text.trim();
    if (addr.isNotEmpty) args.addAll(['--addr', addr]);
    final port = _portController.text.trim();
    if (port.isNotEmpty) args.addAll(['--port', port]);
    if (_runAsDaemon) args.add('--daemon');
    if (_logLevel != 'info') args.addAll(['--log-level', _logLevel]);
    final logFile = _logFileController.text.trim();
    if (logFile.isNotEmpty) args.addAll(['--log-file', logFile]);
    final storageRoot = _rootPathController.text.trim();
    if (storageRoot.isNotEmpty) args.addAll(['--storage-root-path', storageRoot]);

    _activeCommandLine = '${[binaryPath, ...args].map((a) => a.contains(' ') ? "'$a'" : a).join(' ')}';

    final ok = await BackendProcessManager.startProcess(binaryPath, args: args);
    if (mounted) {
      setState(() => _startingProcess = false);
      if (ok) {
        await Future.delayed(const Duration(seconds: 2));
        await Future.wait([_loadPids(), _fetchAndShowConfig()]);
      } else {
        setState(() => _processMessage = l10n.failedToStartBackend);
      }
    }
  }

  Future<void> _fetchAndShowConfig() async {
    setState(() => _loadingUsage = true);
    try {
      final results = await Future.wait([
        _api.getSystemUsage(),
        _api.getSystemConfig(),
      ]);
      final usage = results[0];
      final config = results[1];
      final rootPath = config['storage_root'] as String?;
      if (rootPath != null && rootPath.isNotEmpty) {
        _rootPathController.text = rootPath;
      }
      if (mounted) {
        setState(() {
          _usageData = usage;
          _loadingUsage = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUsage = false);
    }

    // Sync runtime log level and log file from backend
    try {
      final results = await Future.wait([
        _api.getConfig('log_level'),
        _api.getConfig('log_file'),
      ]);
      if (mounted) {
        setState(() {
          final level = results[0];
          if (level != null && _logLevels.contains(level)) _logLevel = level;
          final logFile = results[1];
          if (logFile != null && logFile.isNotEmpty) _logFileController.text = logFile;
        });
      }
    } catch (_) {}
  }

  String _reconstructCommandLine() {
    final binaryPath = _binaryPathController.text.trim();
    if (binaryPath.isEmpty) return '';
    final List<String> args = [];
    final addr = _addrController.text.trim();
    if (addr.isNotEmpty) args.addAll(['--addr', addr]);
    final port = _portController.text.trim();
    if (port.isNotEmpty) args.addAll(['--port', port]);
    if (_runAsDaemon) args.add('--daemon');
    if (_logLevel != 'info') args.addAll(['--log-level', _logLevel]);
    final logFile = _logFileController.text.trim();
    if (logFile.isNotEmpty) args.addAll(['--log-file', logFile]);
    final storageRoot = _rootPathController.text.trim();
    if (storageRoot.isNotEmpty) args.addAll(['--storage-root-path', storageRoot]);
    return [binaryPath, ...args].map((a) => a.contains(' ') ? "'$a'" : a).join(' ');
  }

  Future<void> _pickBinaryFile() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path != null) {
          _binaryPathController.text = path;
          _persistBinaryPath(path);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _logFileDebounce?.cancel();
    _storageRootDebounce?.cancel();
    _rootPathController.dispose();
    _binaryPathController.dispose();
    _addrController.dispose();
    _portController.dispose();
    _logFileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.storageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProcessCard(l10n, theme),
          if (_usageData != null) ...[
            const SizedBox(height: 16),
            _buildDiskUsageCard(l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildDiskUsageCard(AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.storageTitle, style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadUsage,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _loadingUsage
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ))
                : StorageDashboardWidget(usageData: _usageData),
          ],
        ),
      ),
    );
  }

  Future<void> _updateLogLevel(String newLevel) async {
    try {
      await _api.updateConfig('log_level', newLevel);
    } catch (_) {}
  }

  Future<void> _updateLogFile(String path) async {
    try {
      await _api.updateConfig('log_file', path);
    } catch (_) {}
  }

  Future<void> _updateStorageRoot() async {
    final path = _rootPathController.text.trim();
    if (path.isEmpty) return;
    try {
      await _api.updateStorageRoot(path);
      await _persistRootPath(path);
    } catch (_) {}
  }

  Widget _buildProcessCard(AppLocalizations l10n, ThemeData theme) {
    final bool anyRunning = _pids.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.backendProcess, style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadPids,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingPids)
              const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ))
            else if (!anyRunning)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text(l10n.noProcessFound)),
              )
            else
              ..._pids.map((pid) => _buildPidTile(pid, l10n, theme)),
            if (_processMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_processMessage!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            const Divider(height: 8),
            CheckboxListTile(
              value: _runAsDaemon,
              onChanged: anyRunning ? null : (val) => setState(() => _runAsDaemon = val ?? true),
              title: Text(l10n.runAsDaemon),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _binaryPathController,
                    decoration: InputDecoration(
                      labelText: l10n.enterBinaryPath,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: l10n.browse,
                  onPressed: _pickBinaryFile,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _startingProcess ? null : _handleStart,
                icon: _startingProcess
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(l10n.start),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _optionsExpanded = !_optionsExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _optionsExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(l10n.startupOptions,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            if (_optionsExpanded) ...[
              const SizedBox(height: 8),
              _buildOptionsFields(l10n),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsFields(AppLocalizations l10n) {
    final bool running = _pids.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _addrController,
          readOnly: running,
          decoration: InputDecoration(
            labelText: l10n.listenAddressLabel,
            hintText: '0.0.0.0',
            border: const OutlineInputBorder(),
            filled: running,
            fillColor: running ? Theme.of(context).disabledColor.withValues(alpha: 0.08) : null,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _portController,
          readOnly: running,
          decoration: InputDecoration(
            labelText: l10n.portLabel,
            hintText: '9026',
            border: const OutlineInputBorder(),
            filled: running,
            fillColor: running ? Theme.of(context).disabledColor.withValues(alpha: 0.08) : null,
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _logLevel,
          decoration: InputDecoration(
            labelText: l10n.logLevelLabel,
            border: const OutlineInputBorder(),
          ),
          items: _logLevels.map((level) => DropdownMenuItem(
            value: level,
            child: Text(level.toUpperCase()),
          )).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _logLevel = val);
              if (running) _updateLogLevel(val);
            }
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _logFileController,
                decoration: InputDecoration(
                  labelText: l10n.logFileLabel,
                  hintText: 'ainas_backend.log',
                  border: const OutlineInputBorder(),
                ),
                onChanged: running
                    ? (val) {
                        _logFileDebounce?.cancel();
                        _logFileDebounce = Timer(
                            const Duration(milliseconds: 600), () {
                          _updateLogFile(val);
                        });
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: l10n.browse,
              onPressed: () async {
                try {
                  final result = await FilePicker.pickFiles(type: FileType.any);
                  if (result != null && result.files.isNotEmpty) {
                    final path = result.files.single.path;
                    if (path != null) {
                      _logFileController.text = path;
                      if (running) _updateLogFile(path);
                    }
                  }
                } catch (_) {}
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _rootPathController,
                decoration: InputDecoration(
                  labelText: l10n.storageRootPath,
                  hintText: 'storage',
                  border: const OutlineInputBorder(),
                ),
                onChanged: running
                    ? (val) {
                        _storageRootDebounce?.cancel();
                        _storageRootDebounce = Timer(
                            const Duration(milliseconds: 600), _updateStorageRoot);
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: l10n.browse,
              onPressed: () async {
                try {
                  String? selectedDirectory = await FilePicker.getDirectoryPath();
                  if (selectedDirectory != null) {
                    _rootPathController.text = selectedDirectory;
                    if (running) _updateStorageRoot();
                  }
                } catch (_) {}
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPidTile(int pid, AppLocalizations l10n, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 10, height: 10,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${l10n.pidLabel}: $pid'),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l10n.processRunning,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_activeCommandLine != null && _activeCommandLine!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      _activeCommandLine!,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_stoppingPid)
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: Icon(Icons.stop_circle, color: theme.colorScheme.error),
              tooltip: l10n.stop,
              onPressed: () => _handleStop(pid),
            ),
        ],
      ),
    );
  }
}
