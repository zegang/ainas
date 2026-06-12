import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'package:logging/logging.dart';
import '../../../../services/api_service.dart';
import '../../domain/chat_repository_impl.dart';
import '../../../../shared/models/chat_message.dart';
import '../widgets/nas_file_picker.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/chat_repository.dart';
import '../widgets/chat_bubble.dart';

class AIAssistantPage extends StatefulWidget {
  const AIAssistantPage({super.key});

  @override
  State<AIAssistantPage> createState() => _AIAssistantPageState();
}

class _AIAssistantPageState extends State<AIAssistantPage> {
  final _log = Logger('AIAssistantPage');
  final ApiService api = ApiService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<String> _selectedFiles = []; // State to hold selected files
  bool _isAwaitingResponse = false; // State for loading animation
  StreamSubscription<String>? _chatSubscription; // To track current stream
  String? _currentRequestId; // To track current request for backend signal

  late final ChatRepository _repository = HttpChatRepository(
    baseUrl: api.baseUrl,
  );

  List<ChatMessage> get _messages => api.chatHistory;

  void _handleStop() {
    if (_chatSubscription != null) {
      _chatSubscription!.cancel();
      _chatSubscription = null;
    }
    if (_currentRequestId != null) {
      api.cancelAiChat(_currentRequestId!);
      _currentRequestId = null;
    }
    setState(() => _isAwaitingResponse = false);
    _log.info('AI Request cancelled by user');
  }

  void _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedFiles.isEmpty) return; // Don't send empty messages

    _log.info('User sent message: $text');
    final currentFiles = List<String>.from(_selectedFiles); // Capture files for this message

    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, files: currentFiles)); // Store files with message
      _controller.clear();
      _selectedFiles.clear(); // Clear selected files after sending
      _isAwaitingResponse = true; // Show loading animation
      _currentRequestId = requestId;
    });

    _scrollToBottom();

    ChatMessage? assistantMessage;
    String fullResponse = '';

    try {
      _chatSubscription = _repository.streamResponse(text, files: currentFiles, requestId: requestId).listen((chunk) {
        if (!mounted) {
          _log.warning('!mounted is true. existing streamResponse...');
          return;
        }
        
        if (assistantMessage == null) {
          // First chunk received: create assistant message bubble
          setState(() {
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
      }, onDone: () {
        if (mounted) {
          setState(() => _isAwaitingResponse = false);
          _chatSubscription = null;
          _currentRequestId = null;
        }
      }, onError: (e) {
        throw e;
      }, cancelOnError: true);
    } catch (e) {
      _log.severe('Streaming error', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Communication with AI Assistant failed.'),
            backgroundColor: Theme.of(context).colorScheme.error,
            action: SnackBarAction(label: 'RETRY', textColor: Colors.white, onPressed: _handleSend),
          ),
        );
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
    final staged = api.stagedFilesForAi;
    if (staged.isNotEmpty) {
      _selectedFiles.addAll(staged);
      api.stagedFilesForAi.clear();
    }
    _scrollToBottom();
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear History"),
        content: const Text("Are you sure you want to clear the entire chat history?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Clear", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      api.clearChatHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.aiAssistant, style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: l10n.clear,
                  onPressed: _handleClearHistory,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              // Show indicator only if waiting for the very first response chunk
              itemCount: _messages.length + 
                ((_isAwaitingResponse && (_messages.isEmpty || _messages.last.isUser)) ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const _TypingIndicator();
                }
                return _buildMessage(context, _messages[index]);
              },
            ),
          ),
          // Display selected files as chips
          _buildFileThumbnails(
            _selectedFiles,
            isRemovable: true,
            onRemove: (file) {
              setState(() => _selectedFiles.remove(file));
            },
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          ),
          _buildQuickActions(),
          _buildInputArea(),
        ],
      ),
    );
  }

  bool _isImage(String filePath) {
    final ext = filePath.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  String _getFileUrl(String filePath, {bool thumbnail = false}) {
    // Assuming a standard download endpoint on your NAS backend
    return '${api.baseUrl}/api/files/download?path=${Uri.encodeComponent(filePath)}${thumbnail ? "&thumbnail=true" : ""}';
  }

  bool _isMarkdown(String text) {
    // Heuristic: Check for common Markdown syntax indicators
    final markdownPatterns = [
      RegExp(r'^#', multiLine: true),          // Headers
      RegExp(r'\*\*|__'),                       // Bold
      RegExp(r'^\s*[-*+]\s+', multiLine: true), // Unordered lists
      RegExp(r'^\s*\d+\.\s+', multiLine: true), // Ordered lists
      RegExp(r'```'),                           // Code blocks
      RegExp(r'\[.*\]\(.*\)'),                  // Links
    ];
    return markdownPatterns.any((pattern) => pattern.hasMatch(text));
  }

  Widget _buildMessage(BuildContext context, ChatMessage message) {
    if (message.isUser) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (message.files != null && message.files!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0, right: 8.0),
              child: _buildFileThumbnails(message.files!),
            ),
          ChatBubble(message: message),
          _buildMessageActions(context, message, canEdit: true),
          const SizedBox(height: 8),
        ],
      );
    }

    final List<Widget> blocks = [];
    final String fullText = message.text;

    // Regex for blocks that might be unclosed during streaming
    // Matches <tag>content</tag> OR <tag>content (at end of string)
    final thinkRegExp = RegExp(r'<think>([\s\S]*?)(?:</think>|$)');
    final toolRegExp = RegExp(r'<tool_call>([\s\S]*?)(?:</tool_call>|$)');
    final toolResultRegExp = RegExp(r'<tool_result>([\s\S]*?)(?:</tool_result>|$)');

    // Collect all potential matches and their types
    final List<Map<String, dynamic>> allMatches = [];
    for (final m in thinkRegExp.allMatches(fullText)) {
      allMatches.add({'match': m, 'type': 'think'});
    }
    for (final m in toolRegExp.allMatches(fullText)) {
      allMatches.add({'match': m, 'type': 'tool'});
    }
    for (final m in toolResultRegExp.allMatches(fullText)) {
      allMatches.add({'match': m, 'type': 'result'});
    }

    // Sort matches by their starting position in the text
    allMatches.sort((a, b) => (a['match'] as Match).start.compareTo((b['match'] as Match).start));

    int lastEnd = 0;
    for (final item in allMatches) {
      final Match m = item['match'];
      if (m.start < lastEnd) continue; // Skip overlapping tags (e.g., tags inside an unclosed thinking block)

      // Add any text before the tag as a regular chat bubble
      final textBefore = fullText.substring(lastEnd, m.start).trim();
      if (textBefore.isNotEmpty) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: ChatBubble(message: message.copyWith(text: textBefore)),
        ));
      }

      final content = m.group(1)?.trim() ?? "";
      final String tagText = m.group(0) ?? "";

      if (item['type'] == 'think') {
        final isComplete = tagText.contains('</think>');
        if (content.isNotEmpty || !isComplete) {
          blocks.add(_buildThinkingBlock(context, content, isComplete: isComplete));
        }
      } else if (item['type'] == 'tool') {
        final isComplete = tagText.contains('</tool_call>');
        blocks.add(_buildToolCallBlock(context, content, isComplete: isComplete));
      } else if (item['type'] == 'result') {
        final isComplete = tagText.contains('</tool_result>');
        blocks.add(_buildToolResultBlock(context, content, isComplete: isComplete));
      }
      
      // Update lastEnd to the actual end of the matched tag. 
      // Because matches are sorted by start, and we skip overlaps, 
      // this ensures nested tags are "swallowed" into the content of the outer tag.
      lastEnd = m.end;
    }

    // Add remaining text after all tags have been processed
    final remainingText = fullText.substring(lastEnd).trim();
    if (remainingText.isNotEmpty) {
      // Identify if this is the final answer block
      final isFinalAnswer = !allMatches.any((m) => (m['match'] as Match).start > lastEnd);
      
      final textPart = message.copyWith(text: remainingText);
      
      if (isFinalAnswer) {
        // Present the final answer in a "good way" (prominent block)
        blocks.add(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Text("Response", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                  if (_isMarkdown(remainingText)) 
                    Text(" (Markdown)", style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
            ChatBubble(message: textPart),
            _buildMessageActions(context, textPart),
          ],
        ));
      } else {
        blocks.add(ChatBubble(message: textPart));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _buildMessageActions(BuildContext context, ChatMessage message, {bool canEdit = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (canEdit && message.isUser)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              onPressed: () {
                _controller.text = message.text;
                // Move cursor to the end
                _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
              },
              tooltip: "Edit and resend",
            ),
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Copied to clipboard"), duration: Duration(seconds: 1)),
              );
            },
            tooltip: "Copy text",
          ),
        ],
      ),
    );
  }

  void _showFullScreenGallery(BuildContext context, List<String> allFiles, String initialFile) {
    final imageFiles = allFiles.where(_isImage).toList();
    final int initialPage = imageFiles.indexOf(initialFile);

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: PageView.builder(
            controller: PageController(initialPage: initialPage == -1 ? 0 : initialPage),
            itemCount: imageFiles.length,
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(_getFileUrl(imageFiles[index])),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFileThumbnails(
    List<String> files, {
    bool isRemovable = false,
    Function(String)? onRemove,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    if (files.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        alignment: WrapAlignment.end,
        children: files.map((f) {
          final bool isImg = _isImage(f);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: isImg ? () => _showFullScreenGallery(context, files, f) : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: isImg
                        ? Image.network(
                            _getFileUrl(f, thumbnail: true),
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                        : null,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) => const Center(
                              child: Icon(Icons.broken_image_outlined, size: 20, color: Colors.grey),
                            ),
                          )
                        : const Center(child: Icon(Icons.insert_drive_file, size: 24, color: Colors.grey)),
                  ),
                ),
              ),
              if (isRemovable)
                Positioned(
                  top: -6,
                  right: -6,
                  child: GestureDetector(
                    onTap: () => onRemove?.call(f),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 2,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                    ),
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildThinkingBlock(BuildContext context, String thought, {required bool isComplete}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey(isComplete), // Force rebuild to apply initiallyExpanded change
          initiallyExpanded: !isComplete, // Expand automatically while thinking
          dense: true,
          title: Text(
            isComplete ? "Thinking Process" : "Thinking...",
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  thought,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCallBlock(BuildContext context, String jsonContent, {required bool isComplete}) {
    String toolName = "AI Tool";
    try {
      final data = json.decode(isComplete ? jsonContent : "$jsonContent}"); 
      toolName = data['name'] ?? "AI Tool";
    } catch (_) {
      // Partial stream regex fallback to extract tool name before JSON is valid
      final nameMatch = RegExp(r'"name"\s*:\s*"([^"]*)').firstMatch(jsonContent);
      if (nameMatch != null) toolName = nameMatch.group(1)!;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            isComplete ? "Executed: $toolName" : "Calling: $toolName...",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          if (!isComplete) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildToolResultBlock(BuildContext context, String content, {required bool isComplete}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.secondary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_turned_in_outlined, size: 16, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 8),
              Text(
                "Tool Result",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
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
            onPressed: _isAwaitingResponse ? _handleStop : _handleSend,
            icon: _isAwaitingResponse
                ? const _AnimatedStopIcon()
                : const Icon(Icons.send),
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
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: FadeTransition(
          opacity: _animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.2).animate(_animation),
            child: Icon(
              Icons.auto_awesome_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedStopIcon extends StatefulWidget {
  const _AnimatedStopIcon();

  @override
  State<_AnimatedStopIcon> createState() => _AnimatedStopIconState();
}

class _AnimatedStopIconState extends State<_AnimatedStopIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // Adjust duration for desired pulsation speed
    )..repeat(reverse: true); // Repeat the animation back and forth
    _animation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _animation, child: const Icon(Icons.stop));
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