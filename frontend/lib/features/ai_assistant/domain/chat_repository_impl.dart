import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:ainas_frontend/shared/models/chat_message.dart';
import 'chat_repository.dart';


/// A concrete implementation of [ChatRepository] that communicates with the FastAPI backend.
class HttpChatRepository implements ChatRepository {
  final String baseUrl;
  final http.Client _client = http.Client();

  HttpChatRepository({required this.baseUrl});

  @override
  Future<ChatMessage> sendMessage(String text, {List<String>? files}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/ai/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'text': text,
        'files': files ?? [],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return ChatMessage(text: data['text'] ?? '', isUser: false);
    } else {
      throw Exception('Failed to send message: ${response.statusCode}');
    }
  }

  @override
  Stream<String> streamResponse(String text, {List<String>? files, String? requestId}) async* {
    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl/api/ai/chat/stream'),
    );
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'text': text,
      'files': files ?? [],
      if (requestId != null) 'request_id': requestId,
    });

    final response = await _client.send(request);
    if (response.statusCode == 200) {
      yield* response.stream.transform(utf8.decoder);
    } else {
      yield 'Error: Server returned ${response.statusCode}';
    }
  }
}