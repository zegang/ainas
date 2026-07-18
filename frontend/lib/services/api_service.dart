import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'db_service.dart';
import 'settings_service.dart';
import 'file_service.dart';
import 'ai_service.dart';
import 'sync_service.dart';
import 'user_service.dart';
import '../shared/models/chat_message.dart';
import '../shared/models/file_item.dart';
import '../shared/models/upload_models.dart';

class ApiService with ChangeNotifier {
  ApiService._internal() {
    user.addListener(notifyListeners);
    ai.addListener(notifyListeners);
    files.baseUrl = settings.baseUrl;
    sync.baseUrl = settings.baseUrl;
    settings.addListener(_onSettingsChanged);
    files.addListener(notifyListeners);
  }

  void _onSettingsChanged() {
    files.baseUrl = settings.baseUrl;
    sync.baseUrl = settings.baseUrl;
    notifyListeners();
  }

  static final ApiService _instance = ApiService._internal();

  factory ApiService() => _instance;

  final _log = Logger('ApiService');

  final settings = SettingsService();
  final files = FileService();
  final ai = AiService();
  final sync = SyncService();
  final user = UserService();

  set dbService(DbService service) {
    settings.dbService = service;
    files.dbService = service;
    sync.baseUrl = baseUrl;
    user.dbService = service;
  }

  // ── Settings forwarding ──────────────────────────────────────────────
  String get baseUrl => settings.baseUrl;
  String get locale => settings.locale;
  ThemeMode get themeMode => settings.themeMode;
  double get fontScale => settings.fontScale;

  Future<void> loadSettings() async {
    await settings.loadSettings();
    await user.loadSettings();
    sync.listConfigs().catchError((e) {
      _log.warning('Backend unreachable, starting with offline defaults: $e');
    });
    sync.startAutoSync();
  }
  Future<void> updateBaseUrl(String url) => settings.updateBaseUrl(url);
  Future<void> persistBaseUrl(String url) {
    sync.baseUrl = url;
    return settings.persistBaseUrl(url);
  }
  Future<void> persistLocale(String langCode) => settings.persistLocale(langCode);
  Future<void> persistThemeMode(ThemeMode mode) => settings.persistThemeMode(mode);
  Future<void> persistFontScale(double scale) => settings.persistFontScale(scale);

  // ── User forwarding ──────────────────────────────────────────────────
  bool get isLoggedIn => user.isLoggedIn;
  String get username => user.username;
  String get vipStatus => user.vipStatus;

  Future<bool> login(String username, String password) => user.login(username, password);
  Future<void> logout() => user.logout();
  Future<Map<String, dynamic>?> getUserInfo() => user.getUserInfo();
  Future<bool> setPassword(String oldPassword, String newPassword) => user.setPassword(oldPassword, newPassword);
  Future<bool> setIcon(String filePath) => user.setIcon(filePath);

  // ── File forwarding ──────────────────────────────────────────────────
  String get currentPath => files.currentPath;
  List<UploadTask> get uploads => files.uploads;

  void invalidateFileListCache() => files.invalidateFileListCache();
  Future<List<FileItem>> listFiles(String path, {bool forceRefresh = false}) =>
      files.listFiles(path, forceRefresh: forceRefresh);
  Future<void> createFolder(String path) => files.createFolder(path);
  Future<void> deleteItem(String path) => files.deleteItem(path);
  Future<void> renameItem(String path, String newName) => files.renameItem(path, newName);
  Future<void> moveItem(String path, String newPath) => files.moveItem(path, newPath);
  Future<void> copyItem(String path, String targetDir) => files.copyItem(path, targetDir);
  Future<void> copyItems(List<String> paths, String targetDir) => files.copyItems(paths, targetDir);
  void cancelUpload(String taskId) => files.cancelUpload(taskId);
  void clearCompletedUploads() => files.clearCompletedUploads();
  Future<void> retryUpload(String taskId) => files.retryUpload(taskId);
  Future<Map<String, dynamic>> pdfToImages(String path, String outputDir) =>
      files.pdfToImages(path, outputDir);
  Future<Map<String, dynamic>> compressImage(String path, int quality, {int? maxWidth, int? maxHeight, String? outputPath}) =>
      files.compressImage(path, quality, maxWidth: maxWidth, maxHeight: maxHeight, outputPath: outputPath);
  Future<Map<String, dynamic>> mergeToPdf(List<String> filePaths, String outputPath) =>
      files.mergeToPdf(filePaths, outputPath);
  Future<void> uploadFile(String fileName, Uint8List bytes, {String? parentPath}) =>
      files.uploadFile(fileName, bytes, parentPath: parentPath);
  Future<void> uploadFileFromPath(String fileName, String filePath, {String? parentPath}) =>
      files.uploadFileFromPath(fileName, filePath, parentPath: parentPath);
  Future<void> enqueueUploads(List<MapEntry<String, String>> fileEntries, {String? parentPath}) =>
      files.enqueueUploads(fileEntries, parentPath: parentPath);
  Future<void> loadPendingUploads() => files.loadPendingUploads();

  // ── AI forwarding ────────────────────────────────────────────────────
  List<ChatMessage> get chatHistory => ai.chatHistory;
  bool get isAwaitingResponse => ai.isAwaitingResponse;
  set isAwaitingResponse(bool v) => ai.isAwaitingResponse = v;
  String? get currentRequestId => ai.currentRequestId;
  set currentRequestId(String? v) => ai.currentRequestId = v;
  List<String> get stagedFilesForAi => ai.stagedFilesForAi;

  void setWelcomeMessage(String message) => ai.setWelcomeMessage(message);
  void stageFilesForAi(List<String> paths) {
    ai.stageFilesForAi(paths);
    setTabIndex(2);
  }
  void clearChatHistory(String welcomeMessage) => ai.clearChatHistory(welcomeMessage);
  void setupChatStream(Stream<String> repositoryStream) => ai.setupChatStream(repositoryStream);
  Stream<String> getChatStream() => ai.getChatStream();
  void markResponseComplete() => ai.markResponseComplete();
  Future<void> cancelAiChat(String requestId) => ai.cancelAiChat(requestId);
  Future<List<Map<String, dynamic>>> getLocalModels() => ai.getLocalModels();
  Future<List<dynamic>> searchHfModels(String query) => ai.searchHfModels(query);
  Future<Map<String, dynamic>> checkModelDownloaded(String repoId, {String? filename}) =>
      ai.checkModelDownloaded(repoId, filename: filename);
  Future<void> downloadHfModel(String repoId, String? filename) => ai.downloadHfModel(repoId, filename);
  Future<void> deleteModel(String name) => ai.deleteModel(name);
  Future<Map<String, dynamic>> getAiStatus() => ai.getAiStatus();
  Future<Map<String, dynamic>> enableAi() => ai.enableAi();
  Future<Map<String, dynamic>> disableAi() => ai.disableAi();
  Future<Map<String, dynamic>> getFeatures() => ai.getFeatures();
  Future<void> setFeatureModel(String name, String modelName) => ai.setFeatureModel(name, modelName);
  Future<Map<String, dynamic>> getRagStatus() => ai.getRagStatus();
  Future<Map<String, dynamic>> getRagDocuments() => ai.getRagDocuments();
  Future<Map<String, dynamic>> clearRagIndex() => ai.clearRagIndex();
  Future<Map<String, dynamic>> deleteRagDocument(String path) => ai.deleteRagDocument(path);

  // ── Server status ────────────────────────────────────────────────────
  bool isServerConnected = false;
  String aiStatus = 'disabled';
  double storagePercent = 0.0;
  String storageLabel = '';

  // ── Navigation ───────────────────────────────────────────────────────
  int currentTabIndex = 0;

  void setTabIndex(int index) {
    currentTabIndex = index;
    notifyListeners();
  }

  // ── Status ───────────────────────────────────────────────────────────
  Future<bool> checkStatus([String? overrideUrl]) async {
    final targetUrl = overrideUrl ?? baseUrl;
    bool connected = false;

    try {
      final response = await http.get(Uri.parse('$targetUrl/api/status')).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        connected = true;
        final data = json.decode(response.body);
        aiStatus = data['ai_status'] ?? (data['ai_enabled'] == true ? 'ready' : 'disabled');
      }
    } catch (e) {
      _log.warning('Status check failed: $e');
      connected = false;
      aiStatus = 'disabled';
    }

    if (overrideUrl == null || overrideUrl == baseUrl) {
      isServerConnected = connected;
      notifyListeners();
    }
    return connected;
  }

  Future<Map<String, dynamic>> getSystemUsage() async {
    final url = '$baseUrl/api/system/usage';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final free = (data['free_gb'] as num?)?.toDouble() ?? 0.0;
        final total = (data['total_gb'] as num?)?.toDouble() ?? 0.0;
        final used = total - free;
        storagePercent = used / total;
        storageLabel = "${storagePercent.toStringAsFixed(1)}% Used (${free.toStringAsFixed(1)} GB Free)";
        notifyListeners();
        return data;
      }
      throw Exception('Failed to load storage usage');
    } catch (e) {
      _log.severe('Error fetching system usage: $e');
      rethrow;
    }
  }

  // ── Config ───────────────────────────────────────────────────────────
  Future<String?> getConfig(String key) async {
    final url = '$baseUrl/api/config/$key';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final configs = data['configs'] as List?;
        if (configs != null && configs.isNotEmpty) {
          return configs[0]['value'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> updateConfig(String key, String value) async {
    final url = '$baseUrl/api/config/$key';
    _log.info('--> PUT $url');
    final response = await http.put(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'value': value}),
    );
    if (response.statusCode != 200) {
      final data = json.decode(response.body);
      throw Exception(data['message'] ?? 'Failed to update config');
    }
  }

  Future<Map<String, dynamic>> getSystemConfig() async {
    final url = '$baseUrl/api/system/config';
    _log.info('--> GET $url');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load system config');
  }

  Future<Map<String, dynamic>> updateStorageRoot(String path) async {
    final url = '$baseUrl/api/system/storage-root';
    _log.info('--> PATCH $url');
    final response = await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': path}),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Failed to update storage root');
    }
    return data;
  }
}
