import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../shared/models/chat_message.dart';
import '../../../../shared/widgets/viewers/pdf_viewer_page.dart'; // Keep this import as it's a viewer
import '../../../../shared/widgets/viewers/docx_viewer_page.dart'; // Keep this import as it's a viewer

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: message.isUser ? Colors.blue.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.isUser ? "You" : "AI Assistant",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 4),
          MarkdownBody(
            data: message.text,
            onTapLink: (text, href, title) {
              if (href != null) {
                final uri = Uri.parse(href);
                final nasPath = uri.queryParameters['path']?.toLowerCase() ?? '';

                if (nasPath.endsWith('.pdf')) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PdfViewerPage(url: href, title: text),
                    ),
                  );
                } else if (nasPath.endsWith('.docx')) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          DocxViewerPage(url: href, title: text),
                    ),
                  );
                } else {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}