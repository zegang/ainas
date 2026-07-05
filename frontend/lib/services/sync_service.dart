import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import '../shared/models/sync_pair.dart';

class SyncService with ChangeNotifier {
  SyncService._internal();

  static final SyncService _instance = SyncService._internal();

  factory SyncService() => _instance;

  final _log = Logger('SyncService');

  String baseUrl = '';

  List<SyncPair> _configs = [];
  List<SyncPair> get configs => _configs;

  Timer? _autoTimer;
  bool _autoRunning = false;
  final Set<int> _syncingIds = {};
  final Map<int, DateTime> _lastSyncTime = {};
  final Map<int, StreamSubscription<FileSystemEvent>> _watchers = {};
  final Map<int, Timer> _debounceTimers = {};

  void startAutoSync() {
    if (_autoRunning) return;
    _autoRunning = true;
    _autoTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkIntervals());
  }

  void stopAutoSync() {
    _autoRunning = false;
    _autoTimer?.cancel();
    _autoTimer = null;
    for (final sub in _watchers.values) {
      sub.cancel();
    }
    _watchers.clear();
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
  }

  void _checkIntervals() {
    final now = DateTime.now();
    for (final config in _configs) {
      if (!config.enabled || _syncingIds.contains(config.id)) continue;

      if (config.syncPolicy == 'interval') {
        if (config.syncIntervalSecs <= 0) continue;
        final last = _lastSyncTime[config.id];
        if (last != null && now.difference(last).inSeconds < config.syncIntervalSecs) continue;
        _lastSyncTime[config.id] = now;
        _syncInBackground(config);
      } else if (config.syncPolicy == 'daily' && config.syncTime.isNotEmpty) {
        final parts = config.syncTime.split(':');
        if (parts.length >= 2) {
          final target = DateTime(
            now.year, now.month, now.day,
            int.tryParse(parts[0]) ?? 0,
            int.tryParse(parts[1]) ?? 0,
          );
          final diff = now.difference(target).inSeconds;
          if (diff >= 0 && diff < 60) {
            final last = _lastSyncTime[config.id];
            if (last == null || last.day != now.day || last.month != now.month || last.year != now.year) {
              _lastSyncTime[config.id] = now;
              _syncInBackground(config);
            }
          }
        }
      }
    }
  }

  void _setupWatcher(SyncPair config) {
    _watchers[config.id]?.cancel();
    _debounceTimers[config.id]?.cancel();

    try {
      final dir = Directory(config.sourcePath);
      if (!dir.existsSync()) return;

      final sub = dir.watch(recursive: true).listen((event) {
        _debounceTimers[config.id]?.cancel();
        _debounceTimers[config.id] = Timer(const Duration(seconds: 2), () {
          if (config.enabled && !_syncingIds.contains(config.id)) {
            _lastSyncTime[config.id] = DateTime.now();
            _syncInBackground(config);
          }
        });
      });

      _watchers[config.id] = sub;
      _log.info('File watcher set up for config ${config.id} (${config.sourcePath})');
    } catch (e) {
      _log.warning('Failed to set up file watcher for config ${config.id}: $e');
    }
  }

  void _teardownWatcher(int configId) {
    _watchers[configId]?.cancel();
    _watchers.remove(configId);
    _debounceTimers[configId]?.cancel();
    _debounceTimers.remove(configId);
  }

  void _updateWatchers() {
    final watchIds = _configs
        .where((c) => c.enabled && c.syncPolicy == 'watch')
        .map((c) => c.id)
        .toSet();

    for (final id in _watchers.keys.toList()) {
      if (!watchIds.contains(id)) {
        _teardownWatcher(id);
      }
    }

    for (final config in _configs) {
      if (config.enabled && config.syncPolicy == 'watch' && !_watchers.containsKey(config.id)) {
        _setupWatcher(config);
      }
    }
  }

  Future<void> _syncInBackground(SyncPair config) async {
    _syncingIds.add(config.id);
    try {
      final dir = Directory(config.sourcePath);
      if (!await dir.exists()) return;

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

      if (files.isEmpty) return;

      final diffResult = await diffManifest(config.id, files);
      final toUpload = (diffResult['files_to_upload'] as List?) ?? [];

      for (int i = 0; i < toUpload.length; i++) {
        final f = toUpload[i] as Map<String, dynamic>;
        final path = f['path'] as String;
        final localPath = '${dir.path}/$path';
        final file = File(localPath);
        if (!await file.exists()) continue;
        await uploadFile(config.id, localPath, path);
      }

      if (toUpload.isNotEmpty) {
        final uploadedPaths = toUpload.map((f) => f['path'] as String).toList();
        await commitSync(config.id, uploadedPaths);
      }

      if (config.deleteAfterSync) {
        try {
          await for (final entity in dir.list(recursive: false, followLinks: false)) {
            if (entity is Directory) {
              await entity.delete(recursive: true);
            } else {
              await entity.delete();
            }
          }
        } catch (e) {
          _log.warning('auto-sync delete source failed for config ${config.id}: $e');
        }
      }
    } catch (e) {
      _log.warning('auto-sync failed for config ${config.id}: $e');
    } finally {
      _syncingIds.remove(config.id);
      notifyListeners();
    }
  }

  Future<List<SyncPair>> listConfigs() async {
    final url = '$baseUrl/api/sync';
    _log.info('--> GET $url');
    final response = await http.get(Uri.parse(url));
    _log.info('<-- ${response.statusCode} ${response.body.length}');
    if (response.statusCode == 200) {
      try {
        final data = json.decode(response.body);
        final raw = data['configs'];
        if (raw is! List) {
          _log.severe('listConfigs: "configs" is not a List, got: ${raw.runtimeType} body=${response.body}');
          throw Exception('list_sync_failed');
        }
        final list = raw
            .map((e) {
              if (e is! Map<String, dynamic>) {
                _log.severe('listConfigs: item is not Map, got: ${e.runtimeType} item=$e');
                return SyncPair.fromJson({});
              }
              return SyncPair.fromJson(e as Map<String, dynamic>);
            })
            .toList();
        _log.info('listConfigs: loaded ${list.length} configs');
        _configs = list;
        _updateWatchers();
        notifyListeners();
        return list;
      } catch (e) {
        _log.severe('listConfigs: JSON parse error: $e body=${response.body}');
        rethrow;
      }
    }
    _log.severe('listConfigs: HTTP ${response.statusCode} body=${response.body}');
    throw Exception('list_sync_failed');
  }

  Future<SyncPair> getConfig(int id) async {
    final url = '$baseUrl/api/sync/$id';
    _log.info('--> GET $url');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return SyncPair.fromJson(json.decode(response.body));
    }
    throw Exception('get_sync_failed');
  }

  Future<SyncPair> createConfig(SyncPair config) async {
    final url = '$baseUrl/api/sync';
    _log.info('--> POST $url');
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(config.toJson()),
    );
    if (response.statusCode == 200) {
      final created = SyncPair.fromJson(json.decode(response.body));
      await listConfigs();
      return created;
    }
    throw Exception('create_sync_failed');
  }

  Future<SyncPair> updateConfig(SyncPair config) async {
    final url = '$baseUrl/api/sync/${config.id}';
    _log.info('--> PUT $url');
    final response = await http.put(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(config.toJson()),
    );
    if (response.statusCode == 200) {
      final updated = SyncPair.fromJson(json.decode(response.body));
      await listConfigs();
      return updated;
    }
    throw Exception('update_sync_failed');
  }

  Future<void> deleteConfig(int id) async {
    final url = '$baseUrl/api/sync/$id';
    _log.info('--> DELETE $url');
    try {
      final response = await http.delete(Uri.parse(url)).timeout(const Duration(seconds: 10));
      _log.info('<-- DELETE ${response.statusCode}');
      if (response.statusCode == 200) {
        await listConfigs();
        return;
      }
      throw Exception('delete_sync_failed status=${response.statusCode}');
    } catch (e) {
      _log.severe('deleteConfig error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getStats(int id) async {
    final url = '$baseUrl/api/sync/$id/stats';
    _log.info('--> GET $url');
    final response = await http.get(Uri.parse(url));
    _log.info('<-- GET ${response.statusCode} ${response.body.length}');
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    _log.severe('getStats: HTTP ${response.statusCode} body=${response.body}');
    throw Exception('get_sync_stats_failed');
  }

  Future<bool> toggleConfig(int id) async {
    final url = '$baseUrl/api/sync/$id/toggle';
    _log.info('--> PATCH $url');
    final response = await http.patch(Uri.parse(url));
    if (response.statusCode == 200) {
      await listConfigs();
      return true;
    }
    throw Exception('toggle_sync_failed');
  }

  Future<Map<String, dynamic>> diffManifest(int id, List<Map<String, dynamic>> files) async {
    final url = '$baseUrl/api/sync/$id/sync';
    _log.info('--> POST $url (${files.length} files)');
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'files': files}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('sync_diff_failed');
  }

  Future<void> uploadFile(int id, String localFilePath, String relativePath) async {
    final url = '$baseUrl/api/sync/$id/upload';
    _log.info('--> POST $url ($relativePath)');
    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.files.add(await http.MultipartFile.fromPath('file', localFilePath));
    request.fields['path'] = relativePath;
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw Exception('sync_upload_failed: $relativePath');
    }
  }

  Future<void> commitSync(int id, List<String> paths) async {
    final url = '$baseUrl/api/sync/$id/commit';
    _log.info('--> POST $url (${paths.length} files)');
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'paths': paths}),
    );
    if (response.statusCode != 200) {
      throw Exception('sync_commit_failed');
    }
  }

  Future<void> downloadFile(int id, String relativePath, String localFilePath) async {
    final url = '$baseUrl/api/sync/$id/download?path=${Uri.encodeComponent(relativePath)}';
    _log.info('--> GET $url');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final file = File(localFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
      _log.info('    downloaded to $localFilePath (${response.bodyBytes.length} bytes)');
    } else {
      throw Exception('sync_download_failed: $relativePath');
    }
  }
}
