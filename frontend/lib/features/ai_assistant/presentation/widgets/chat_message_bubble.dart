import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ainas_frontend/shared/models/chat_message.dart';
import 'package:ainas_frontend/shared/widgets/viewers/pdf_viewer_page.dart';
import 'package:ainas_frontend/shared/widgets/viewers/docx_viewer_page.dart';

class PdfLinkBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  PdfLinkBuilder(this.context);

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle, inlineWidgets) {
    final href = element.attributes['href'];
    if (href == null) return null;

    final uri = Uri.parse(href);
    final nasPath = uri.queryParameters['path']?.toLowerCase() ?? '';
    if (!nasPath.endsWith('.pdf')) return null;

    final thumbnailUrl = Uri.parse(href).replace(
      queryParameters: {
        ...uri.queryParametersAll,
        'thumbnail': ['true'],
      },
    ).toString();

    final name = nasPath.split('/').last;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PdfViewerPage(url: href, title: name),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: thumbnailUrl,
                  width: 48,
                  height: 64,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 48,
                    height: 64,
                    color: Colors.grey[200],
                    child: const Icon(Icons.picture_as_pdf, size: 24),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 48,
                    height: 64,
                    color: Colors.grey[200],
                    child: const Icon(Icons.picture_as_pdf, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
            builders: {
              'link': PdfLinkBuilder(context),
            },
            onTapLink: (text, href, title) {
              if (href != null) {
                final uri = Uri.parse(href);
                final nasPath = uri.queryParameters['path']?.toLowerCase() ?? '';

                if (nasPath.endsWith('.docx')) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          DocxViewerPage(url: href, title: text),
                    ),
                  );
                } else if (!nasPath.endsWith('.pdf')) {
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