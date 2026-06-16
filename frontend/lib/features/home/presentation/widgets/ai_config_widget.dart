import 'package:flutter/material.dart';

class AiConfigWidget extends StatelessWidget {
  final Map<String, dynamic>? modelConfig;
  final Map<String, dynamic>? ragStatus;
  final VoidCallback? onRefresh;

  const AiConfigWidget({super.key, this.modelConfig, this.ragStatus, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Active AI Models", style: Theme.of(context).textTheme.titleMedium),
                    if (onRefresh != null)
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: onRefresh,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
                const Divider(),
                _buildModelRow(context, "Chat", modelConfig?['chat_model'], Icons.chat_bubble_outline),
                _buildModelParams(context, "chat"),
                _buildModelRow(context, "Vision", modelConfig?['vision_model'], Icons.remove_red_eye_outlined),
                _buildModelParams(context, "vision"),
                _buildModelRow(context, "Embedding", modelConfig?['embedding_model'], Icons.hub_outlined),
                _buildModelParams(context, "embedding"),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("RAG & Search Engine", style: Theme.of(context).textTheme.titleMedium),
                    if (onRefresh != null)
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: onRefresh,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
                const Divider(),
                _buildRagInfo(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModelRow(BuildContext context, String task, String? name, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text("$task:", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(name?.split('/').last ?? "Loading...", overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildModelParams(BuildContext context, String prefix) {
    if (modelConfig == null) return const SizedBox.shrink();
    final List<Widget> params = [];
    
    final ctx = modelConfig!['${prefix}_context_size'];
    final temp = modelConfig!['${prefix}_temperature'];
    final tok = modelConfig!['${prefix}_max_tokens'];

    if (ctx != null) params.add(_buildParam(context, "Ctx", "$ctx"));
    if (temp != null) params.add(_buildParam(context, "Temp", "$temp"));
    if (tok != null) params.add(_buildParam(context, "Max", "$tok"));

    if (params.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 30, bottom: 8),
      child: Wrap(spacing: 12, children: params),
    );
  }

  Widget _buildParam(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildRagInfo(BuildContext context) {
    final isConnected = ragStatus?['status'] == 'connected';
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Text("Elasticsearch: ${ragStatus?['status'] ?? 'Unknown'}"),
          ],
        ),
        const SizedBox(height: 8),
        _buildDetailRow("Address", ragStatus?['address'] ?? "N/A"),
        _buildDetailRow("Index", ragStatus?['index'] ?? "N/A"),
        _buildDetailRow("Usage", "${ragStatus?['usage_docs'] ?? 0} indexed documents"),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}