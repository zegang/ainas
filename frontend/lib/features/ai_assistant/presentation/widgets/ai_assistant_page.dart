import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'package:logging/logging.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/features/ai_assistant/domain/chat_repository_impl.dart';
import 'package:ainas_frontend/shared/models/chat_message.dart';
import './nas_file_picker.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/features/ai_assistant/domain/chat_repository.dart';
import 'package:ainas_frontend/features/ai_assistant/presentation/widgets/chat_bubble.dart';
import 'package:ainas_frontend/shared/widgets/viewers/pdf_viewer_page.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AIAssistantPage extends StatefulWidget {
  const AIAssistantPage({super.key});

  @override
  State<AIAssistantPage> createState() => _AIAssistantPageState();
}

class _AIAssistantPageState extends State<AIAssistantPage> with SingleTickerProviderStateMixin {
  final _log = Logger('AIAssistantPage');
  final ApiService api = ApiService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<String> _selectedFiles = [];
  late AnimationController _borderAnimController;
  late Animation<double> _borderAnimation;
  late FocusNode _textFocusNode;
  StreamSubscription<String>? _localSubscription;
  FlutterTts? _flutterTts;
  String? _speakingMessageId;

  late final ChatRepository _repository = HttpChatRepository(
    baseUrl: api.baseUrl,
  );

  List<ChatMessage> get _messages => api.chatHistory;

  void _handleStop() {
    if (_localSubscription != null) {
      _localSubscription!.cancel();
      _localSubscription = null;
    }
    if (api.currentRequestId != null) {
      api.cancelAiChat(api.currentRequestId!);
    }
    api.markResponseComplete();
    setState(() {}); // Trigger rebuild with updated api state
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
    });

    api.isAwaitingResponse = true;
    api.currentRequestId = requestId;
    api.notifyListeners();

    _scrollToBottom();

    try {
      final stream = _repository.streamResponse(text, files: currentFiles, requestId: requestId, history: _messages);
      // Setup the stream in ApiService to keep it alive across page navigation.
      // ApiService now accumulates chunks directly into chatHistory,
      // so the response is preserved even without a UI listener.
      api.setupChatStream(stream);
      
      // Listen to the broadcast stream for live UI updates (rebuild + scroll)
      _localSubscription = api.getChatStream().listen((chunk) {
        if (!mounted) {
          _log.warning('!mounted is true. existing streamResponse...');
          return;
        }
        setState(() {});
        _scrollToBottom();
      }, onDone: () {
        if (mounted) {
          setState(() {});
          _localSubscription = null;
        }
      }, onError: (e) {
        throw e;
      }, cancelOnError: false);
    } catch (e) {
      _log.severe('Streaming error', e);
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.communicationFailed),
            backgroundColor: Theme.of(context).colorScheme.error,
            action: SnackBarAction(label: l10n.retryAction, textColor: Colors.white, onPressed: _handleSend),
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
    _borderAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _borderAnimation = Tween<double>(begin: 0, end: 360).animate(_borderAnimController);
    _textFocusNode = FocusNode();
    _textFocusNode.onKey = (node, event) {
      if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
        if (!event.isShiftPressed || event.isControlPressed) {
          if (!api.isAwaitingResponse) {
            _handleSend();
          }
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };
    // Initialize welcome message with localization support
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final l10n = AppLocalizations.of(context)!;
      if (api.chatHistory.isEmpty) {
        api.setWelcomeMessage(l10n.aiWelcomeMessage);
      }
      
      // Always animate the input border
      _borderAnimController.repeat();

      // Reconnect to ongoing or completed AI response
      if (api.isAwaitingResponse) {
        _localSubscription = api.getChatStream().listen((chunk) {
          if (!mounted) return;
          setState(() {});
          _scrollToBottom();
        });
        _log.info('Reconnected to ongoing AI response (requestId: ${api.currentRequestId})');
      } else if (_messages.isNotEmpty && !_messages.last.isUser) {
        // Response completed while page was away — data is already in chatHistory
        setState(() {});
        _log.info('Reconnected to completed AI response');
      }
    });
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
    try { _flutterTts?.stop(); } catch (_) {}
    _textFocusNode.dispose();
    _borderAnimController.dispose();
    _localSubscription = null;
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleSpeech(String messageId, String text) {
    if (_speakingMessageId == messageId) {
      try { _flutterTts?.stop(); } catch (_) {}
      _speakingMessageId = null;
    } else {
      _flutterTts ??= FlutterTts();
      try {
        _flutterTts?.stop();
        final locale = Localizations.localeOf(context);
        _flutterTts?.setLanguage(locale.languageCode == 'zh' ? 'zh-CN' : 'en-US');
        _flutterTts?.speak(text);
        _speakingMessageId = messageId;
      } catch (_) {
        _speakingMessageId = null;
        _flutterTts = null;
      }
    }
    setState(() {});
  }

  String _messageId(ChatMessage msg) => msg.timestamp.millisecondsSinceEpoch.toString();

  void _handleClearHistory() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearHistoryTitle),
        content: Text(l10n.clearHistoryConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancelButton)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.clear, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      api.clearChatHistory(l10n.aiWelcomeMessage);
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
                ((api.isAwaitingResponse && (_messages.isEmpty || _messages.last.isUser)) ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const _TypingIndicator();
                }
                return _buildMessage(context, _messages[index]);
              },
            ),
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
    final cleanPath = filePath.startsWith('/') ? filePath.substring(1) : filePath;
    return '${api.baseUrl}/api/files/download?path=${Uri.encodeComponent(cleanPath)}${thumbnail ? "&thumbnail=true" : ""}';
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
    final l10n = AppLocalizations.of(context)!;
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

    // Regex for blocks that might be unclosed during streaming.
    // We use lookaheads to prevent a block from swallowing subsequent tags 
    // if the model forgets a closing tag or is still streaming.
    final thinkRegExp = RegExp(r'<think>([\s\S]*?)(?:</think>|(?=<tool_call>|<tool_result>|<think>)|$)');
    final toolRegExp = RegExp(r'<tool_call>([\s\S]*?)(?:</tool_call>|(?=<think>|<tool_result>|<tool_call>)|$)');
    final toolResultRegExp = RegExp(r'<tool_result>([\s\S]*?)(?:</tool_result>|(?=<think>|<tool_call>|<tool_result>)|$)');

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
          child: ChatBubble(message: message.copyWith(text: textBefore), isMarkdown: _isMarkdown(textBefore)),
        ));
      }

      final content = m.group(1)?.trim() ?? "";
      final String tagText = m.group(0) ?? "";
      
      // A block is "complete" if it has its explicit closing tag 
      // OR if the stream has moved on (the match doesn't end at the string's current end).
      final bool isActuallyAtEnd = m.end == fullText.length;

      if (item['type'] == 'think') {
        final isComplete = tagText.contains('</think>') || !isActuallyAtEnd;
        if (content.isNotEmpty || !isComplete) {
          blocks.add(_buildThinkingBlock(context, content, isComplete: isComplete));
        }
      } else if (item['type'] == 'tool') {
        final isComplete = tagText.contains('</tool_call>') || !isActuallyAtEnd;
        blocks.add(_buildToolCallBlock(context, content, isComplete: isComplete));
      } else if (item['type'] == 'result') {
        final isComplete = tagText.contains('</tool_result>') || !isActuallyAtEnd;
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
                  Text(l10n.responseLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                  if (_isMarkdown(remainingText)) 
                    Text(l10n.markdownLabel, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
            ChatBubble(message: textPart, isMarkdown: _isMarkdown(remainingText)),
            _buildMessageActions(context, textPart),
          ],
        ));
      } else {
        blocks.add(ChatBubble(message: textPart, isMarkdown: _isMarkdown(remainingText)));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _buildMessageActions(BuildContext context, ChatMessage message, {bool canEdit = false}) {
    final l10n = AppLocalizations.of(context)!;
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
              tooltip: l10n.editAndResend,
            ),
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 16),
            onPressed: () {
              final l10n = AppLocalizations.of(context)!;
              Clipboard.setData(ClipboardData(text: message.text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.copiedToClipboard), duration: const Duration(seconds: 1)),
              );
            },
            tooltip: l10n.copyText,
          ),
          IconButton(
            icon: Icon(
              _speakingMessageId == _messageId(message) ? Icons.volume_up : Icons.volume_up_outlined,
              size: 16,
            ),
            onPressed: () => _toggleSpeech(_messageId(message), message.text),
            tooltip: _speakingMessageId == _messageId(message) ? l10n.stopSpeaking : l10n.readAloud,
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
                  child: CachedNetworkImage(imageUrl: _getFileUrl(imageFiles[index])),
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
    WrapAlignment alignment = WrapAlignment.end,
  }) {
    if (files.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        alignment: alignment,
        children: files.map((f) {
          final bool isImg = _isImage(f);
          final bool isPdf = f.toLowerCase().endsWith('.pdf');
          return Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: isImg
                    ? () => _showFullScreenGallery(context, files, f)
                    : isPdf
                        ? () {
                            final url = _getFileUrl(f);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PdfViewerPage(
                                  url: url,
                                  title: f.split('/').last,
                                ),
                              ),
                            );
                          }
                        : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: isImg || isPdf
                        ? CachedNetworkImage(
                            imageUrl: _getFileUrl(f, thumbnail: true),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 40,
                            placeholder: (context, url) => Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (context, url, error) => Icon(
                              isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          )
                        : const Center(child: Icon(Icons.insert_drive_file, size: 18, color: Colors.grey)),
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
    final l10n = AppLocalizations.of(context)!;
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
            isComplete ? l10n.thinkingProcess : l10n.thinking,
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
    final l10n = AppLocalizations.of(context)!;
    String toolName = l10n.aiToolName;
    try {
      final data = json.decode(isComplete ? jsonContent : "$jsonContent}"); 
      toolName = data['name'] ?? l10n.aiToolName;
    } catch (_) {
      // Partial stream regex fallback to extract tool name before JSON is valid
      final nameMatch = RegExp(r'"name"\s*:\s*"([^"]*)').firstMatch(jsonContent);
      if (nameMatch != null) {
        toolName = nameMatch.group(1)!;
      } else {
        toolName = l10n.aiToolName;
      }
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
            isComplete ? l10n.toolExecuted(toolName) : l10n.toolCalling(toolName),
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
    final l10n = AppLocalizations.of(context)!;
    String displayContent = content;
    String? duration;

    // Parse duration if present (e.g., "[0.52s] Tool 'name' result: ...")
    final durationMatch = RegExp(r'\[([\d\.]+)s\]').firstMatch(content);
    if (durationMatch != null) {
      duration = durationMatch.group(1);
      displayContent = content.substring(durationMatch.end).trim();
    }

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
                duration != null ? l10n.toolResultWithDuration(duration) : l10n.toolResult,
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
            displayContent,
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _QuickActionChip(
            label: l10n.checkStorage,
            onTap: api.isAwaitingResponse ? null : () => _controller.text = l10n.checkStoragePrompt,
          ),
          _QuickActionChip(
            label: l10n.searchDocuments,
            onTap: api.isAwaitingResponse ? null : () => _controller.text = l10n.searchDocumentsPrompt,
          ),
          _QuickActionChip(
            label: l10n.optimizeNas,
            onTap: api.isAwaitingResponse ? null : () => _controller.text = l10n.optimizeNasPrompt,
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 4.0, 12.0, 12.0),
      child: AnimatedBuilder(
        animation: _borderAnimation,
        builder: (context, child) {
          final borderColor = HSLColor.fromAHSL(1, _borderAnimation.value, 0.8, 0.5).toColor();
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: child,
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: _buildFileThumbnails(
                  _selectedFiles,
                  isRemovable: true,
                  alignment: WrapAlignment.start,
                  onRemove: (file) {
                    setState(() => _selectedFiles.remove(file));
                  },
                ),
              ),
            TextField(
              controller: _controller,
              focusNode: _textFocusNode,
              enabled: !api.isAwaitingResponse,
              minLines: 1,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: l10n.askAiHint,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  tooltip: l10n.attachFiles,
                  onPressed: api.isAwaitingResponse
                      ? null
                      : () async {
                          final List<String>? result = await showModalBottomSheet<List<String>>(
                            context: context,
                            isScrollControlled: true,
                            builder: (context) => FractionallySizedBox(
                              heightFactor: 0.9,
                              child: NasFilePicker(initialSelectedFiles: _selectedFiles),
                            ),
                          );
                          if (result != null) {
                            setState(() => _selectedFiles = result);
                          }
                        },
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 4),
                  child: IconButton.filled(
                    onPressed: api.isAwaitingResponse ? _handleStop : _handleSend,
                    icon: api.isAwaitingResponse
                        ? const _AnimatedStopIcon()
                        : const Icon(Icons.send),
                  ),
                ),
              ],
            ),
          ],
        ),
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
  final VoidCallback? onTap;

  const _QuickActionChip({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(label: Text(label), onPressed: onTap),
    );
  }
}