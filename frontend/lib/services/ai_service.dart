import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'settings_service.dart';
import '../shared/models/chat_message.dart';

class AiService with ChangeNotifier {
  AiService._internal();

  static final AiService _instance = AiService._internal();

  factory AiService() => _instance;

  final _log = Logger('AiService');

  String get _baseUrl => SettingsService().baseUrl;

  // ── Chat / AI Assistant ──────────────────────────────────────────────
  final List<ChatMessage> chatHistory = [];

  void setWelcomeMessage(String message) {
    chatHistory.clear();
    chatHistory.add(ChatMessage(text: message, isUser: false));
    notifyListeners();
  }

  bool isAwaitingResponse = false;
  String? currentRequestId;
  StreamSubscription<String>? _activeChatSubscription;
  final StreamController<String> _chatStreamController = StreamController<String>.broadcast();
  StringBuffer? _responseBuffer;

  final List<String> stagedFilesForAi = [];

  void stageFilesForAi(List<String> paths) {
    stagedFilesForAi.addAll(paths);
    notifyListeners();
    _log.info('Staged ${paths.length} files for AI Assistant');
  }

  void clearChatHistory(String welcomeMessage) {
    chatHistory.clear();
    chatHistory.add(ChatMessage(text: welcomeMessage, isUser: false));
    isAwaitingResponse = false;
    currentRequestId = null;
    _responseBuffer = null;
    _activeChatSubscription?.cancel();
    _activeChatSubscription = null;
    notifyListeners();
  }

  void setupChatStream(Stream<String> repositoryStream) {
    _activeChatSubscription?.cancel();
    _responseBuffer = null;

    _activeChatSubscription = repositoryStream.listen(
      (chunk) {
        _appendResponseChunk(chunk);
        _chatStreamController.add(chunk);
        notifyListeners();
      },
      onDone: () {
        _responseBuffer = null;
        markResponseComplete();
      },
      onError: (e) {
        _chatStreamController.addError(e);
        _responseBuffer = null;
        markResponseComplete();
      },
      cancelOnError: false,
    );
  }

  void _appendResponseChunk(String chunk) {
    final buf = _responseBuffer;
    if (buf == null) {
      _responseBuffer = StringBuffer(chunk);
      chatHistory.add(ChatMessage(text: chunk, isUser: false));
    } else {
      buf.write(chunk);
      if (chatHistory.isNotEmpty && !chatHistory.last.isUser) {
        chatHistory[chatHistory.length - 1] = chatHistory.last.copyWith(text: buf.toString());
      }
    }
  }

  Stream<String> getChatStream() => _chatStreamController.stream;

  void markResponseComplete() {
    isAwaitingResponse = false;
    currentRequestId = null;
    notifyListeners();
  }

  Future<void> cancelAiChat(String requestId) async {
    final url = '$_baseUrl/api/ai/chat/cancel/$requestId';
    _log.info('--> POST $url');
    try {
      await http.post(Uri.parse(url));
    } catch (e) {
      _log.warning('Failed to send cancel signal: $e');
    }
  }

  // ── RAG ──────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getRagStatus() async {
    final url = '$_baseUrl/api/ai/rag';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load RAG status');
    }
  }

  Future<Map<String, dynamic>> getRagDocuments() async {
    final url = '$_baseUrl/api/ai/rag/documents';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load RAG documents');
    }
  }

  Future<Map<String, dynamic>> clearRagIndex() async {
    final url = '$_baseUrl/api/ai/rag';
    final response = await http.delete(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final detail = json.decode(response.body)['detail'] ?? 'Unknown error';
      throw Exception('Failed to clear RAG index: $detail');
    }
  }

  Future<Map<String, dynamic>> deleteRagDocument(String path) async {
    final url = '$_baseUrl/api/ai/rag/documents?path=${Uri.encodeComponent(path)}';
    final response = await http.delete(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final detail = json.decode(response.body)['detail'] ?? 'Unknown error';
      throw Exception('Failed to delete RAG document: $detail');
    }
  }

  // ── Models ───────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getLocalModels() async {
    final url = '$_baseUrl/api/ai/models';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body)['models']);
    } else {
      throw Exception('Failed to list models');
    }
  }

  Future<List<dynamic>> searchHfModels(String query) async {
    final url = '$_baseUrl/api/ai/models/hf';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'query': query}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to search HF models');
    }
  }

  Future<Map<String, dynamic>> checkModelDownloaded(String repoId, {String? filename}) async {
    final url = '$_baseUrl/api/ai/models/check';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'repo_id': repoId, 'filename': filename}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to check model status');
    }
  }

  Future<void> downloadHfModel(String repoId, String? filename) async {
    final url = '$_baseUrl/api/ai/models/download';
    final body = <String, dynamic>{'repo_id': repoId};
    if (filename != null && filename.isNotEmpty) {
      body['filename'] = filename;
    }
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to download model');
    }
  }

  Future<void> deleteModel(String name) async {
    final url = '$_baseUrl/api/ai/models';
    final response = await http.delete(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete model');
    }
  }

  // ── AI Engine ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getAiStatus() async {
    final url = '$_baseUrl/api/ai/status';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load AI status');
    }
  }

  Future<Map<String, dynamic>> enableAi() async {
    final url = '$_baseUrl/api/ai/enable';
    final response = await http.post(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to enable AI');
  }

  Future<Map<String, dynamic>> disableAi() async {
    final url = '$_baseUrl/api/ai/disable';
    final response = await http.post(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to disable AI');
  }

  // ── Features ─────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getFeatures() async {
    final url = '$_baseUrl/api/ai/features';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      return {
        'features': List<Map<String, dynamic>>.from(body['features'] ?? []),
        'status': body['status'] ?? 'ready',
      };
    } else if (response.statusCode == 503) {
      return {'features': <Map<String, dynamic>>[], 'status': 'loading'};
    } else {
      throw Exception('Failed to load features');
    }
  }

  Future<void> setFeatureModel(String name, String modelName) async {
    final url = '$_baseUrl/api/ai/features/$name/model';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'model_name': modelName}),
    );
    if (response.statusCode != 200 && response.statusCode != 202) {
      final detail = json.decode(response.body)['detail'] ?? 'Unknown error';
      throw Exception('Failed to set feature model: $detail');
    }
  }
}
