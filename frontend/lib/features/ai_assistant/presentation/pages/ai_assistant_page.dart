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
  bool _isAwaitingResponse = false; // State for loading animation

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
      _isAwaitingResponse = true; // Show loading animation
    });

    _scrollToBottom();

    ChatMessage? assistantMessage;
    String fullResponse = '';

    try {
      await for (final chunk in _repository.streamResponse(text, files: currentFiles)) {
        if (!mounted) break;

        if (assistantMessage == null) {
          // First chunk received: stop animation and create bubble
          setState(() {
            _isAwaitingResponse = false;
            assistantMessage = ChatMessage(text: '', isUser: false);
            _messages.add(assistantMessage!);
          });
        }

        fullResponse += chunk;
        setState(() {
          // Update the last message in the list with the accumulated text
          _messages[_messages.length - 1] = assistantMessage!.copyWith(
            text: fullResponse,
            isUser: false,
            timestamp: assistantMessage!.timestamp,
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
    } finally {
      if (mounted) {
        setState(() => _isAwaitingResponse = false);
      }
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
  void initState() {
    super.initState();
    // Check for files staged from the File Browser
    final staged = ApiService().stagedFilesForAi;
    if (staged.isNotEmpty) {
      _selectedFiles.addAll(staged);
      ApiService().stagedFilesForAi.clear();
    }
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
              itemCount: _messages.length + (_isAwaitingResponse ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const _TypingIndicator();
                }
                return _buildMessage(context, _messages[index]);
              },
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

  Widget _buildMessage(BuildContext context, ChatMessage message) {
    if (message.isUser) return ChatBubble(message: message);

    // Regex to detect <think>...</think> tags
    final regExp = RegExp(r'<think>(.*?)</think>', dotAll: true);
    final match = regExp.firstMatch(message.text);

    if (match != null) {
      final thought = match.group(1)?.trim() ?? "";
      final response = message.text.replaceFirst(regExp, '').trim();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapsible Reasoning Block
          Container(
            margin: const EdgeInsets.only(bottom: 8, left: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                dense: true,
                title: Text(
                  "Thinking Process",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      thought,
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Main Answer Bubble
          if (response.isNotEmpty) ChatBubble(message: message.copyWith(text: response)),
        ],
      );
    }

    return ChatBubble(message: message);
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

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12),
        child: const SizedBox(width: 40, child: LinearProgressIndicator(minHeight: 2)),
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