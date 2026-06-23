import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';

class AiRagWidget extends StatefulWidget {
  final Map<String, dynamic>? ragStatus;
  final VoidCallback? onRefresh;
  final bool showDetails;

  const AiRagWidget({
    super.key,
    this.ragStatus,
    this.onRefresh,
    this.showDetails = true,
  });

  @override
  State<AiRagWidget> createState() => _AiRagWidgetState();
}

class _AiRagWidgetState extends State<AiRagWidget> {
  final _api = ApiService();
  List<Map<String, dynamic>> _documents = [];
  bool _docsLoading = false;
  String? _docsError;

  Future<void> _loadDocuments() async {
    setState(() { _docsLoading = true; _docsError = null; });
    try {
      final result = await _api.getRagDocuments();
      if (mounted) setState(() {
        _documents = (result['files'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ?? [];
        _docsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _docsLoading = false; _docsError = e.toString(); });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.showDetails) _loadDocuments();
  }

  void _handleRefresh() {
    _loadDocuments();
    widget.onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isConnected = widget.ragStatus?['status'] == 'connected';
    return Card(
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: widget.showDetails
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RagDetailsPage(
                      ragStatus: widget.ragStatus,
                      onRefresh: widget.onRefresh,
                    ),
                  ),
                );
              },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.ragSearchEngine, style: Theme.of(context).textTheme.titleMedium),
                  if (widget.onRefresh != null)
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: _handleRefresh,
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
              const Divider(),
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
                  Text(l10n.elasticsearchStatus(widget.ragStatus?['status'] ?? l10n.unknownLabel)),
                ],
              ),
              const SizedBox(height: 8),
              _buildDetailRow(l10n.addressLabel, widget.ragStatus?['address'] ?? l10n.naLabel),
              _buildDetailRow(l10n.indexLabel, widget.ragStatus?['index'] ?? l10n.naLabel),
              _buildDetailRow(l10n.usageLabel, l10n.indexedDocuments(widget.ragStatus?['usage_docs'] ?? 0)),
              if (widget.showDetails) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.indexedDocumentsTitle, style: Theme.of(context).textTheme.titleSmall),
                    if (_documents.isNotEmpty)
                      Text('${_documents.length}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 4),
                if (_docsLoading)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ))
                else if (_docsError != null)
                  Text(_docsError!, style: TextStyle(fontSize: 11, color: Colors.red.shade400))
                else if (_documents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l10n.noDocumentsLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  )
                else
                  ..._documents.take(20).map((doc) {
                    final filename = doc['filename'] as String? ?? '';
                    final path = doc['path'] as String?;
                    final chunkCount = doc['chunk_count'] as int?;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined, size: 18),
                      title: Text(filename, overflow: TextOverflow.ellipsis),
                      subtitle: path != null
                          ? Text('$path (${chunkCount ?? 1} chunks)',
                              style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis)
                          : null,
                    );
                  }),
              ],
            ],
          ),
        ),
      ),
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

class RagDetailsPage extends StatefulWidget {
  final Map<String, dynamic>? ragStatus;
  final VoidCallback? onRefresh;

  const RagDetailsPage({super.key, this.ragStatus, this.onRefresh});

  @override
  State<RagDetailsPage> createState() => _RagDetailsPageState();
}

class _RagDetailsPageState extends State<RagDetailsPage> {
  final _api = ApiService();
  List<Map<String, dynamic>> _documents = [];
  bool _docsLoading = false;
  String? _docsError;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() { _docsLoading = true; _docsError = null; });
    try {
      final result = await _api.getRagDocuments();
      if (mounted) setState(() {
        _documents = (result['files'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ?? [];
        _docsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _docsLoading = false; _docsError = e.toString(); });
    }
  }

  Future<void> _confirmDeleteDocument(BuildContext context, String path, String filename) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.ragDeleteDocTitle),
        content: Text(l10n.ragDeleteDocConfirm(filename)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteButton, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.deleteRagDocument(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.ragDeleteDocSuccess(filename))),
        );
        _loadDocuments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.ragDeleteDocFailed(e.toString()))),
        );
      }
    }
  }

  Future<void> _confirmClearIndex(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.ragClearIndexTitle),
        content: Text(l10n.ragClearIndexConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.clearAllButton, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.clearRagIndex();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.ragClearIndexSuccess)),
        );
        _loadDocuments();
        widget.onRefresh?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.ragClearIndexFailed(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isConnected = widget.ragStatus?['status'] == 'connected';
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.search, size: 20),
            const SizedBox(width: 8),
            Text(l10n.ragSearchEngine),
          ],
        ),
        actions: [
          if (widget.onRefresh != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () {
                _loadDocuments();
                widget.onRefresh?.call();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.elasticsearchStatus(widget.ragStatus?['status'] ?? l10n.unknownLabel),
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildRow(l10n.addressLabel, widget.ragStatus?['address'] ?? l10n.naLabel),
                  _buildRow(l10n.indexLabel, widget.ragStatus?['index'] ?? l10n.naLabel),
                  _buildRow(l10n.usageLabel, l10n.indexedDocuments(widget.ragStatus?['usage_docs'] ?? 0)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.indexedDocumentsTitle, style: Theme.of(context).textTheme.titleMedium),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_documents.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('${_documents.length}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                    ),
                  IconButton(
                    icon: Icon(Icons.delete_sweep, size: 20, color: Colors.red.shade300),
                    tooltip: l10n.ragClearIndexTooltip,
                    onPressed: () => _confirmClearIndex(context),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_docsLoading)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ))
          else if (_docsError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_docsError!, style: TextStyle(color: Colors.red.shade400)),
            )
          else if (_documents.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.noDocumentsLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
            )
          else
            ..._documents.map((doc) {
              final filename = doc['filename'] as String? ?? '';
              final path = doc['path'] as String? ?? '';
              final chunkCount = doc['chunk_count'] as int?;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.description_outlined, size: 18),
                title: Text(filename, overflow: TextOverflow.ellipsis),
                subtitle: path.isNotEmpty
                    ? Text('$path (${chunkCount ?? 1} chunks)',
                        style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                  onPressed: () => _confirmDeleteDocument(context, path, filename),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
