import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/ai_assistant/domain/models/chat_message.dart';
import 'connection_helper.dart';

class FileItem {
  final String name;
  final String path;
  final bool isDir;
  final List<String> tags;
  final int size;
  final DateTime updatedAt;
  final DateTime createdAt;

  FileItem({
    required this.name,
    required this.path,
    required this.isDir,
    this.tags = const [],
    this.size = 0,
    required this.updatedAt,
    required this.createdAt,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      name: json['name'],
      path: json['path'] ?? json['name'],
      isDir: json['is_dir'],
      tags: List<String>.from(json['tags'] ?? []),
      size: json['size'] ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(((json['updated_at'] ?? 0) * 1000).toInt()),
      createdAt: DateTime.fromMillisecondsSinceEpoch(((json['created_at'] ?? 0) * 1000).toInt()),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileItem &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          isDir == other.isDir;

  @override
  int get hashCode => path.hashCode ^ isDir.hashCode;
}

enum UploadStatus { pending, uploading, completed, failed, canceled }

class UploadTask {
  final String id;
  final String fileName;
  final String parentPath;
  final Uint8List bytes;
  double progress; // 0.0 to 1.0
  UploadStatus status;
  String? errorMessage;
  http.Client? _client;

  UploadTask({
    required this.id,
    required this.fileName,
    required this.parentPath,
    required this.bytes,
    this.progress = 0.0,
    this.status = UploadStatus.pending,
  });
}

/// A [http.MultipartRequest] that tracks upload progress by wrapping the stream.
class ProgressMultipartRequest extends http.MultipartRequest {
  ProgressMultipartRequest(super.method, super.url, {required this.onProgress});

  final void Function(int bytes, int total) onProgress;

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    int bytesWritten = 0;

    return http.ByteStream(byteStream.map((List<int> data) {
      bytesWritten += data.length;
      onProgress(bytesWritten, total);
      return data;
    }));
  }
}

class ApiService with ChangeNotifier {
  // 1. Private internal constructor
  ApiService._internal();

  // 2. The single instance of the service
  static final ApiService _instance = ApiService._internal();

  // 3. Factory constructor that always returns the same instance
  factory ApiService() => _instance;

  final _log = Logger('ApiService');

  // Shared state: Default values synchronized with bootstrap.sh via dart-define
  String baseUrl = 'http://${const String.fromEnvironment('NAS_HOST', defaultValue: 'localhost')}:${const String.fromEnvironment('NAS_PORT', defaultValue: '9026')}';
  static const String _baseUrlKey = 'nas_base_url';
  static const String _localeKey = 'nas_locale';
  static const String _themeModeKey = 'nas_theme_mode';
  String locale = 'en';
  ThemeMode themeMode = ThemeMode.system;
  String currentPath = ''; // Tracks the directory currently being navigated by the user
  final List<UploadTask> uploads = [];
  
  bool isServerConnected = false;
  double storagePercent = 0.0; // 0.0 to 1.0
  String storageLabel = "Loading...";

  // Persisted chat history for the AI Assistant during the current session
  final List<ChatMessage> chatHistory = [
    ChatMessage(
      text: "Hello! I'm your AI Assistant. How can I help you manage your NAS today?",
      isUser: false,
    ),
  ];

  // Staging area for AI Assistant attachments
  final List<String> stagedFilesForAi = [];

  void stageFilesForAi(List<String> paths) {
    stagedFilesForAi.addAll(paths);
    notifyListeners();
    _log.info('Staged ${paths.length} files for AI Assistant');
  }

  void clearChatHistory() {
    chatHistory.clear();
    chatHistory.add(ChatMessage(
      text: "Hello! I'm your AI Assistant. How can I help you manage your NAS today?",
      isUser: false,
    ));
    notifyListeners();
  }

  Future<void> updateBaseUrl(String url) async {
    _log.info('To update base URL from $baseUrl to $url');
    baseUrl = url;
    persistBaseUrl(baseUrl);
  }

  /// Sends a signal to the backend to stop a specific AI request.
  Future<void> cancelAiChat(String requestId) async {
    final url = '$baseUrl/ai/chat/cancel/$requestId';
    _log.info('--> POST $url');
    try {
      await http.post(Uri.parse(url));
    } catch (e) {
      _log.warning('Failed to send cancel signal: $e');
    }
  }

  /// Persists the base URL to local storage.
  Future<void> persistBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
    baseUrl = url;
    notifyListeners();
    _log.info('Persisted new base URL: $url');
  }

  /// Persists the locale to local storage.
  Future<void> persistLocale(String langCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, langCode);
    locale = langCode;
    notifyListeners();
    _log.info('Persisted new locale: $langCode');
  }

  /// Persists the theme mode to local storage.
  Future<void> persistThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name); // Store enum as string
    themeMode = mode;
    notifyListeners();
    _log.info('Persisted new theme mode: $mode');
  }

  /// Loads persisted settings from local storage.
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_baseUrlKey) ?? baseUrl;
    locale = prefs.getString(_localeKey) ?? locale;
    final savedThemeMode = prefs.getString(_themeModeKey);
    if (savedThemeMode != null) {
      themeMode = ThemeMode.values.firstWhere(
        (e) => e.name == savedThemeMode,
        orElse: () => ThemeMode.system, // Fallback if stored value is invalid
      );
    }
    notifyListeners();
    _log.info('Loaded base URL: $baseUrl');
  }

  /// Verifies connectivity to the backend by calling the status endpoint.
  Future<bool> checkStatus([String? overrideUrl]) async {
    final connected = await ConnectionHelper.checkStatus(overrideUrl ?? baseUrl);
    if (overrideUrl == null || overrideUrl == baseUrl) {
      isServerConnected = connected;
      // Placeholder for storage info - in production, this would come from a backend API
      if (connected) {
        storagePercent = 0.65; 
        storageLabel = "650 GB / 1 TB";
      }
      notifyListeners();
    }
    return connected;
  }

  Future<List<FileItem>> listFiles(String path) async {
    final url = '$baseUrl/api/files?path=$path';
    _log.info('--> GET $url');

    // Update the navigation context so subsequent uploads go to the right folder
    currentPath = path;

    final response = await http.get(Uri.parse(url));
    _log.info('<-- ${response.statusCode} $url');
    _log.fine('Response Headers: ${response.headers}');

    if (response.statusCode == 200) {
      List data = json.decode(response.body)['items'];
      return data.map((item) => FileItem.fromJson(item)).toList();
    } else {
      _log.severe('API Error Detail - Status: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to load files');
    }
  }

  Future<void> createFolder(String path) async {
    final url = '$baseUrl/api/files/folder';
    _log.info('--> POST $url');
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': path}),
    );
    if (response.statusCode != 200) throw Exception('Failed to create folder');
  }

  Future<void> deleteItem(String path) async {
    final url = '$baseUrl/api/files?path=$path';
    _log.info('--> DELETE $url');
    final response = await http.delete(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete item');
    }
  }

  Future<void> renameItem(String path, String newName) async {
    final url = '$baseUrl/api/files/rename';
    _log.info('--> PATCH $url');
    final response = await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': path, 'new_name': newName}),
    );
    if (response.statusCode != 200) throw Exception('Failed to rename');
  }

  Future<void> moveItem(String path, String newPath) async {
    final url = '$baseUrl/api/files/move';
    _log.info('--> PATCH $url');
    final response = await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': path, 'new_path': newPath}),
    );
    if (response.statusCode != 200) throw Exception('Failed to move');
  }

  void cancelUpload(String taskId) {
    final index = uploads.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      uploads[index]._client?.close();
      uploads[index].status = UploadStatus.canceled;
      notifyListeners();
    }
  }

  void clearCompletedUploads() {
    uploads.removeWhere((t) => t.status == UploadStatus.completed || t.status == UploadStatus.canceled);
    notifyListeners();
  }

  Future<void> retryUpload(String taskId) async {
    final index = uploads.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = uploads[index];
    task.status = UploadStatus.uploading;
    task.progress = 0.0;
    task.errorMessage = null;
    notifyListeners();

    await _performUpload(task);
  }

  Future<void> uploadFile(String fileName, Uint8List bytes, {String? parentPath}) async {
    final taskId = DateTime.now().millisecondsSinceEpoch.toString() + fileName;
    // Default to the current navigated path if no specific path is provided
    final targetPath = parentPath ?? currentPath;
    final task = UploadTask(
      id: taskId,
      fileName: fileName,
      parentPath: targetPath,
      bytes: bytes,
      status: UploadStatus.uploading,
    );
    uploads.add(task);
    notifyListeners();
    await _performUpload(task);
  }

  Future<void> _performUpload(UploadTask task) async {
    final client = http.Client();
    task._client = client;

    try {
      final encodedPath = Uri.encodeComponent(task.parentPath);
      final uploadUrl = '$baseUrl/api/upload?path=$encodedPath';
      _log.info('Uploading file "${task.fileName}" to $uploadUrl');

      final request = ProgressMultipartRequest(
        'POST',
        Uri.parse(uploadUrl),
        onProgress: (bytes, total) {
          task.progress = total > 0 ? bytes / total : 0.0;
          notifyListeners();
        },
      );

      request.files.add(http.MultipartFile.fromBytes('file', task.bytes, filename: task.fileName));

      final response = await client.send(request);
      
      if (response.statusCode == 200) {
        task.status = UploadStatus.completed;
        task.progress = 1.0;
        _log.info('Successfully uploaded "${task.fileName}"');
      } else {
        final respBody = await response.stream.bytesToString();
        task.status = UploadStatus.failed;
        task.errorMessage = "Status ${response.statusCode}";
        _log.severe('Upload failed for "${task.fileName}": $respBody');
      }
    } catch (e) {
      if (task.status != UploadStatus.canceled) {
        task.status = UploadStatus.failed;
        task.errorMessage = e.toString();
      }
      _log.severe('Upload error for "${task.fileName}": $e');
    } finally {
      client.close();
      notifyListeners();
    }
  }
}
