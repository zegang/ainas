

import 'package:ainas_frontend/shared/models/chat_message.dart';

/// Repository interface for interacting with AI Assistant services.
abstract class ChatRepository {
  /// Sends a message to the AI and returns the complete response.
  Future<ChatMessage> sendMessage(String text, {List<String>? files});

  /// Returns a stream of response chunks for real-time "typing" effects.
  Stream<String> streamResponse(String text, {List<String>? files, String? requestId});
}
