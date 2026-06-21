import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/models/chat_message.dart'; // Already moved
import '../shared/models/file_item.dart'; // Already moved
import '../shared/models/upload_models.dart'; // New import
import 'connection_helper.dart';
import 'progress_multipart_request.dart'; // New import

class ApiService with ChangeNotifier {
  // 1. Private internal constructor
  ApiService._internal();

  // 2. The single instance of the service
  static final ApiService _instance = ApiService._internal();

  // 3. Factory constructor that always returns the same instance
  factory ApiService() => _instance;

  final _log = Logger('ApiService');

  // Shared state: Default values synchronized with bootstrap.sh via dart-define
  String baseUrl = 'http://${const String.fromEnvironment('AINAS_ADDR', defaultValue: 'localhost')}:${const String.fromEnvironment('AINAS_PORT', defaultValue: '9026')}';
  static const String _baseUrlKey = 'nas_base_url';
  static const String _localeKey = 'nas_locale';
  static const String _themeModeKey = 'nas_theme_mode';
  static const String _loggedInKey = 'nas_logged_in';
  static const String _usernameKey = 'nas_username';
  static const String _vipStatusKey = 'nas_vip_status';
  String locale = 'en';
  ThemeMode themeMode = ThemeMode.system;
  bool isLoggedIn = false;
  String username = 'Guest';
  String vipStatus = 'Visitor';
  String currentPath = ''; // Tracks the directory currently being navigated by the user
  final List<UploadTask> uploads = [];
  
  bool isServerConnected = false;
  String aiStatus = 'disabled'; // 'disabled', 'initializing', 'ready'
  double storagePercent = 0.0; // 0.0 to 1.0
  String storageLabel = "Loading...";

  // Navigation state to control the app shell tabs
  int currentTabIndex = 0; // 0: Home, 1: Files, 2: AI, 3: Mine
  void setTabIndex(int index) {
    currentTabIndex = index;
    notifyListeners();
  }

  // Persisted chat history for the AI Assistant during the current session
  final List<ChatMessage> chatHistory = [];

  /// Sets the initial welcome message for the chat (called from UI with localized text).
  void setWelcomeMessage(String message) {
    chatHistory.clear();
    chatHistory.add(ChatMessage(
      text: message,
      isUser: false,
    ));
    notifyListeners();
  }

  // Chat state that persists across page navigation
  bool isAwaitingResponse = false;
  String? currentRequestId;
  StreamSubscription<String>? _activeChatSubscription; // Active subscription kept alive across pages
  final StreamController<String> _chatStreamController = StreamController<String>.broadcast();

  // Staging area for AI Assistant attachments
  final List<String> stagedFilesForAi = [];

  void stageFilesForAi(List<String> paths) {
    stagedFilesForAi.addAll(paths);
    setTabIndex(2); // Jump to AI Assistant page (Tab index 2)
    notifyListeners();
    _log.info('Staged ${paths.length} files for AI Assistant');
  }

  void clearChatHistory(String welcomeMessage) {
    chatHistory.clear();
    chatHistory.add(ChatMessage(
      text: welcomeMessage,
      isUser: false,
    ));
    isAwaitingResponse = false;
    currentRequestId = null;
    _activeChatSubscription?.cancel();
    _activeChatSubscription = null;
    notifyListeners();
  }

  /// Connects the repository stream to the internal broadcast stream controller.
  /// This keeps the subscription alive across page navigation while allowing
  /// multiple listeners via the broadcast stream.
  void setupChatStream(Stream<String> repositoryStream) {
    // Cancel any existing subscription
    _activeChatSubscription?.cancel();
    
    // Subscribe to repository stream and forward to broadcast controller
    _activeChatSubscription = repositoryStream.listen(
      (chunk) => _chatStreamController.add(chunk),
      onDone: () => markResponseComplete(),
      onError: (e) {
        _chatStreamController.addError(e);
        markResponseComplete();
      },
      cancelOnError: false,
    );
  }

  /// Returns the broadcast stream for UI listeners to connect to.
  Stream<String> getChatStream() => _chatStreamController.stream;

  /// Marks the response as received (called when stream completes).
  void markResponseComplete() {
    isAwaitingResponse = false;
    currentRequestId = null;
    notifyListeners();
  }

  Future<void> updateBaseUrl(String url) async {
    _log.info('To update base URL from $baseUrl to $url');
    baseUrl = url;
    persistBaseUrl(baseUrl);
  }

  /// Sends a signal to the backend to stop a specific AI request.
  Future<void> cancelAiChat(String requestId) async {
    final url = '$baseUrl/api/ai/chat/cancel/$requestId';
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
    isLoggedIn = prefs.getBool(_loggedInKey) ?? false;
    username = prefs.getString(_usernameKey) ?? 'Guest';
    vipStatus = prefs.getString(_vipStatusKey) ?? (isLoggedIn ? 'VIP Member' : 'Visitor');
    if (!isLoggedIn) {
      username = 'Guest';
      vipStatus = 'Visitor';
    }
    notifyListeners();
    _log.info('Loaded base URL: $baseUrl');
  }

  /// Marks the user as logged in.
  Future<void> login(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, true);
    await prefs.setString(_usernameKey, username);
    await prefs.setString(_vipStatusKey, 'VIP Member');
    isLoggedIn = true;
    this.username = username;
    vipStatus = 'VIP Member';
    notifyListeners();
    _log.info('User logged in: $username');
  }

  /// Logs the user out and clears the local login state.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, false);
    await prefs.setString(_usernameKey, 'Guest');
    await prefs.setString(_vipStatusKey, 'Visitor');
    isLoggedIn = false;
    username = 'Guest';
    vipStatus = 'Visitor';
    notifyListeners();
    _log.info('User logged out');
  }

  /// Verifies connectivity to the backend by calling the status endpoint.
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

  /// Fetches the current storage usage from the backend.
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

  /// Fetches the active AI model configuration.
  Future<Map<String, dynamic>> getAiConfig() async {
    final url = '$baseUrl/api/ai/config/models';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load AI config');
    }
  }

  /// Fetches the RAG/Elasticsearch status.
  Future<Map<String, dynamic>> getRagStatus() async {
    final url = '$baseUrl/api/ai/rag';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load RAG status');
    }
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
      uploads[index].client?.close();
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
    task.client = client;

    try {
      final encodedPath = Uri.encodeComponent(task.parentPath);
      final uploadUrl = '$baseUrl/api/files/upload?path=$encodedPath';
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

  /// Sends a prompt to the AI Assistant and processes the streaming response.
  /// It parses tool results to extract document references for citations.
  Future<void> sendStreamingChat(String text) async {
    final userMsg = ChatMessage(text: text, isUser: true);
    chatHistory.add(userMsg);
    
    final aiMsg = ChatMessage(text: '...', isUser: false);
    chatHistory.add(aiMsg);
    
    final files = stagedFilesForAi.join(',');
    stagedFilesForAi.clear();
    notifyListeners();

    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    final url = '$baseUrl/api/ai/chat/stream?text=${Uri.encodeComponent(text)}&files=${Uri.encodeComponent(files)}&request_id=$requestId';
    
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    
    try {
      final response = await client.send(request);
      final Map<String, String> references = {};
      String fullContent = '';

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        fullContent += chunk;
        
        // Extract citations from tool results (e.g., "- filename.pdf (path/to/file):")
        final citationRegex = RegExp(r"- ([^(\n]+) \(([^)]+)\):");
        final matches = citationRegex.allMatches(fullContent);
        for (final m in matches) {
          final filename = m.group(1)?.trim();
          final path = m.group(2)?.trim();
          if (filename != null && path != null) {
            references[filename] = path;
          }
        }

        // Clean up the text for display by removing the raw tool result blocks
        // and appending the unique references as a "Sources" footer.
        String displayContent = fullContent
            .replaceAll(RegExp(r"<tool_result>[\s\S]*?</tool_result>"), "")
            .trim();
            
        if (references.isNotEmpty) {
          final links = references.entries.map((e) {
            final downloadUrl = '$baseUrl/api/files/download?path=${Uri.encodeComponent(e.value)}';
            return "[${e.key}]($downloadUrl)";
          }).join(', ');
          displayContent += "\n\n**Sources:** $links";
        }
        
        aiMsg.text = displayContent;
        notifyListeners();
      }
    } catch (e) {
      aiMsg.text = "Connection lost: $e";
      notifyListeners();
    } finally {
      client.close();
    }
  }
}
