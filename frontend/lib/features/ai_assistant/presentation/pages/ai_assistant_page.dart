import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import '../../../../services/api_service.dart';
import '../../domain/chat_repository_impl.dart';
import '../../domain/models/chat_message.dart';
import '../widgets/nas_file_picker.dart';
import '../../domain/chat_repository.dart';
import '../widgets/chat_bubble.dart';

class AIAssistantPage extends StatefulWidget {
  const AIAssistantPage({super.key});

  @override
  State<AIAssistantPage> createState() => _AIAssistantPageState();
}

class _AIAssistantPageState extends State<AIAssistantPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<String> _selectedFiles = []; // State to hold selected files

  late final ChatRepository _repository = HttpChatRepository(
    baseUrl: ApiService().baseUrl,
  );

  final List<ChatMessage> _messages = [
    ChatMessage(
      text: "Hello! I'm your AI Assistant. How can I help you manage your NAS today?",
      isUser: false,
    ),
  ];

  void _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedFiles.isEmpty) return; // Don't send empty messages

    developer.log('User sent message: $text', name: 'ai.assistant');
    final currentFiles = List<String>.from(_selectedFiles); // Capture files for this message

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, files: currentFiles)); // Store files with message
      _controller.clear();
      _selectedFiles.clear(); // Clear selected files after sending
    });

    
    _scrollToBottom();

    // Prepare an empty assistant message that will be updated by the stream
    final assistantMessage = ChatMessage(text: '', isUser: false);
    setState(() {
      _messages.add(assistantMessage);
    }); // Add an empty message for the assistant's response

    String fullResponse = '';
    try {
      await for (final chunk in _repository.streamResponse(text, files: currentFiles)) {
        if (!mounted) break;
        fullResponse += chunk;
        setState(() {
          // Update the last message in the list with the accumulated text
          _messages[_messages.length - 1] = assistantMessage.copyWith(
            text: fullResponse,
            isUser: false,
            timestamp: assistantMessage.timestamp,
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      developer.log('Streaming error', name: 'ai.assistant', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Communication with AI Assistant failed.'),
            backgroundColor: Theme.of(context).colorScheme.error,
            action: SnackBarAction(label: 'RETRY', textColor: Colors.white, onPressed: _handleSend),
          ),
        );
      }
      setState(() {
        _messages.removeLast(); // Remove the incomplete assistant bubble
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) => ChatBubble(message: _messages[index]),
            ),
          ),
          // Display selected files as chips
          if (_selectedFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: _selectedFiles.map((f) => Chip(
                  label: Text(f, style: const TextStyle(fontSize: 12)),
                  onDeleted: () => setState(() => _selectedFiles.remove(f)),
                )).toList(),
              ),
            ),
          _buildQuickActions(),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _QuickActionChip(
            label: "Check Storage", 
            onTap: () => _controller.text = "How much storage is left?",
          ),
          _QuickActionChip(
            label: "Search Documents", 
            onTap: () => _controller.text = "Find all PDF files in /Home",
          ),
          _QuickActionChip(
            label: "Optimize NAS", 
            onTap: () => _controller.text = "Run a performance check",
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
      child: Row(
        children: [
          // Button to add files
          IconButton(
            icon: const Icon(Icons.attach_file),
            tooltip: "Attach files",
            onPressed: () async {
              final List<String>? result = await showModalBottomSheet<List<String>>(
                context: context,
                isScrollControlled: true, // Make it full screen
                builder: (context) => FractionallySizedBox(
                  heightFactor: 0.9, // Take up 90% of screen height
                  child: NasFilePicker(initialSelectedFiles: _selectedFiles),
                ),
              );
              if (result != null) {
                setState(() => _selectedFiles = result);
              }
            },
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "Ask the AI assistant...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onSubmitted: (_) => _handleSend(),
            ),
          ),
          IconButton.filled(
            onPressed: _handleSend,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickActionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(label: Text(label), onPressed: onTap),
    );
  }
}