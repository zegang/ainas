import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/shared/widgets/ai_rag_widget.dart';
import 'package:ainas_frontend/features/mine/presentation/widgets/ai_config_page.dart';

class AiConfigWidget extends StatefulWidget {
  final Map<String, dynamic>? ragStatus;
  final Map<String, dynamic>? aiStatus;
  final VoidCallback? onRefresh;
  final bool showLocalModelCard;
  final bool showFeatureIcons;
  final bool showRagDetails;
  final bool showRagSection;

  const AiConfigWidget({
    super.key,
    this.ragStatus,
    this.aiStatus,
    this.onRefresh,
    this.showLocalModelCard = true,
    this.showFeatureIcons = true,
    this.showRagDetails = true,
    this.showRagSection = true,
  });

  @override
  State<AiConfigWidget> createState() => _AiConfigWidgetState();
}

class _AiConfigWidgetState extends State<AiConfigWidget> {
  final _api = ApiService();
  List<Map<String, dynamic>> _models = [];
  bool _modelsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadModels().then((_) => _pollIfDownloading());
  }

  Future<void> _loadModels() async {
    try {
      final models = await _api.getLocalModels();
      if (mounted) setState(() { _models = models; _modelsLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _modelsLoading = false; });
    }
  }

  void _pollIfDownloading() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return false;
      final hasDownloading = _models.any((m) =>
          m['download_start_at'] != null && m['downloaded_at'] == null);
      if (!hasDownloading) return false;
      try {
        final models = await _api.getLocalModels();
        if (mounted) setState(() => _models = models);
        return mounted && _models.any((m) =>
            m['download_start_at'] != null && m['downloaded_at'] == null);
      } catch (_) {
        return false;
      }
    });
  }

  static int? _progressFromModel(Map<String, dynamic> m) {
    final currentTotal = m['current_total_size'] as int?;
    final totalSize = m['total_size'] as int?;
    if (currentTotal != null && totalSize != null && totalSize > 0) {
      return (currentTotal * 100 / totalSize).round();
    }
    return null;
  }

  static const _featureIcons = <String, IconData>{
    'chat': Icons.chat_bubble_outline,
    'vision': Icons.remove_red_eye_outlined,
    'embedding': Icons.hub_outlined,
  };

  void _handleRefresh() {
    _loadModels();
    widget.onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final aiStatus = widget.aiStatus;
    final features = _features(aiStatus);
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
                    Text(l10n.activeAiModels, style: Theme.of(context).textTheme.titleMedium),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildStatusBadge(context, aiStatus),
                        if (widget.onRefresh != null)
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: _handleRefresh,
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ],
                ),
                const Divider(),
                _buildFeatureCardBody(context, aiStatus, features),
              ],
            ),
          ),
        ),
        if (widget.showLocalModelCard) ...[
          const SizedBox(height: 8),
          _buildLocalModelsSection(context),
        ],
        if (widget.showRagSection) ...[
          const SizedBox(height: 8),
          AiRagWidget(
            ragStatus: widget.ragStatus,
            onRefresh: widget.onRefresh,
            showDetails: false,
          ),
        ],
      ],
    );
  }

  Widget _buildFeatureCardBody(BuildContext context, Map<String, dynamic>? aiStatus, List<Map<String, dynamic>> features) {
    final l10n = AppLocalizations.of(context)!;
    final body = _isError(aiStatus)
        ? _buildErrorState(context, aiStatus)
        : _isLoading(aiStatus) && features.isEmpty
            ? _buildLoadingState(context, aiStatus)
            : features.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: features.map((f) => _buildFeatureRow(context, f)).toList(),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l10n.noFeaturesRegistered,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  );
    if (widget.showFeatureIcons) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AiConfigPage()),
        );
      },
      child: body,
    );
  }

  bool _isLoading(Map<String, dynamic>? s) => s?['status'] == 'loading';
  bool _isError(Map<String, dynamic>? s) => s?['status'] == 'error';

  List<Map<String, dynamic>> _features(Map<String, dynamic>? aiStatus) {
    final raw = aiStatus?['features'] as List<dynamic>?;
    if (raw == null || raw.isEmpty) return [];
    return raw.cast<Map<String, dynamic>>();
  }

  Widget _buildStatusBadge(BuildContext context, Map<String, dynamic>? aiStatus) {
    final status = aiStatus?['status'];
    if (status == 'ready' || status == 'disabled') return const SizedBox.shrink();
    if (status == 'error') {
      return Tooltip(
        message: aiStatus?['error'] ?? 'Unknown error',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red.shade700),
              const SizedBox(width: 4),
              Text('Error', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
            ],
          ),
        ),
      );
    }
    final elapsed = aiStatus?['elapsed'] ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange.shade700),
          ),
          const SizedBox(width: 4),
          Text('${elapsed}s', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context, Map<String, dynamic>? aiStatus) {
    final l10n = AppLocalizations.of(context)!;
    final elapsed = aiStatus?['elapsed'] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 8),
          Text('${l10n.aiEngineLoading} ($elapsed s)',
              style: Theme.of(context).textTheme.bodySmall),
          if ((aiStatus?['models_available'] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${aiStatus!['models_available']} models available',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Map<String, dynamic>? aiStatus) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 40, color: Colors.red.shade300),
          const SizedBox(height: 8),
          Text(l10n.aiEngineError, style: Theme.of(context).textTheme.bodySmall),
          if (aiStatus?['error'] != null) ...[
            const SizedBox(height: 4),
            Text(aiStatus!['error'], style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
          ],
        ],
      ),
    );
  }

  Widget _buildLocalModelsSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.localModels, style: Theme.of(context).textTheme.titleMedium),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download, size: 20),
                      tooltip: l10n.downloadModelTitle,
                      onPressed: () => _showDownloadDialog(context),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    if (widget.onRefresh != null)
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: _handleRefresh,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ],
            ),
            const Divider(),
            if (_modelsLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ))
            else if (_models.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.noLocalModels),
              )
            else
              ..._models.map((m) {
                final name = m['name'] as String? ?? '';
                final parts = name.split('/');
                final displayName = parts.isNotEmpty ? parts.last : name;
                final isReady = m['is_ready'] == true;
                final isActive = m['is_active'] == true;
                final progress = _progressFromModel(m);
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.model_training),
                  title: Text(displayName),
                  subtitle: name != displayName
                      ? Text(name, style: Theme.of(context).textTheme.bodySmall)
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isReady && progress != null && progress >= 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 10, height: 10,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange.shade700),
                              ),
                              const SizedBox(width: 4),
                              Text('$progress%', style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                            ],
                          ),
                        )
                      else if (!isReady)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 10, height: 10,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange.shade700),
                              ),
                              const SizedBox(width: 4),
                              Text(l10n.notReadyLabel, style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(l10n.readyLabel, style: TextStyle(fontSize: 10, color: Colors.green.shade700)),
                        ),
                      if (isActive)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary, size: 18),
                        ),
                    ],
                  ),
                  onTap: () => openModelDetailPage(context, m),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(BuildContext context, Map<String, dynamic> feature) {
    final l10n = AppLocalizations.of(context)!;
    final name = feature['name'] as String? ?? '';
    final modelName = feature['model_name'] as String?;
    final icon = _featureIcons[name] ?? Icons.smart_toy_outlined;
    final fStatus = feature['status'] as String?;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text("${feature['feature_title'] ?? name}:", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: fStatus == 'loading'
                ? Row(
                    children: [
                      SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(modelName?.split('/').last ?? 'Loading...',
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                    ],
                  )
                : fStatus == 'error'
                    ? Row(
                        children: [
                          Icon(Icons.error_outline, size: 14, color: Colors.red),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              feature['error'] as String? ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      )
                    : Text(modelName?.split('/').last ?? l10n.notSetLabel,
                        overflow: TextOverflow.ellipsis),
          ),
          if (widget.showFeatureIcons)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade600),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onSelected: (value) {
                if (value == 'change') {
                  _showModelSelector(context, name, modelName);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'change',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz, size: 18, color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      Text(l10n.changeModelLabel, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
    if (!widget.showFeatureIcons) return row;
    return InkWell(
      onTap: () => _showFeatureDetailDialog(context, feature),
      child: row,
    );
  }

  void _showFeatureDetailDialog(BuildContext context, Map<String, dynamic> feature) {
    final l10n = AppLocalizations.of(context)!;
    final name = feature['name'] as String? ?? '';
    final title = feature['feature_title'] as String? ?? name;
    final description = feature['feature_description'] as String?;
    final modelName = feature['model_name'] as String?;
    final fStatus = feature['status'] as String?;
    final fError = feature['error'] as String?;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(_featureIcons[name] ?? Icons.smart_toy_outlined, size: 20),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (description != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                ),
              _detailRowStatic(l10n.modelNameLabel, modelName ?? l10n.notSetLabel),
              _detailRowStatic(l10n.modelStatusLabel, fStatus ?? l10n.unknownLabel),
              if (fError != null)
                _detailRowStatic('Error', fError),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showModelSelector(context, name, modelName);
            },
            child: Text(l10n.changeModelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancelButton),
          ),
        ],
      ),
    );
  }

  void _showModelSelector(BuildContext context, String featureName, [String? currentModel]) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.setModelTitle(featureName)),
        content: SizedBox(
          width: double.maxFinite,
          child: _modelsLoading
              ? const Center(child: CircularProgressIndicator())
              : _models.isEmpty
                  ? Text(l10n.noLocalModels)
                  : ListView(
                      shrinkWrap: true,
                      children: _models.map((m) {
                        final mName = m['name'] as String? ?? '';
                        final mReady = m['is_ready'] == true;
                        final isCurrent = mName == currentModel;
                        return RadioListTile<String>(
                          title: Row(
                            children: [
                              Expanded(child: Text(mName.split('/').last, overflow: TextOverflow.ellipsis)),
                              if (mReady)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(l10n.readyLabel, style: TextStyle(fontSize: 9, color: Colors.green.shade700)),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(l10n.notReadyLabel, style: TextStyle(fontSize: 9, color: Colors.orange.shade700)),
                                ),
                            ],
                          ),
                          subtitle: Text(mName, style: const TextStyle(fontSize: 11)),
                          value: mName,
                          groupValue: currentModel,
                          selected: isCurrent,
                          onChanged: isCurrent
                              ? null
                              : (selected) async {
                                  Navigator.pop(ctx);
                                  try {
                                    await _api.setFeatureModel(featureName, selected!);
                                    if (mounted) _handleRefresh();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(l10n.setModelTitle(selected.split('/').last))),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$e')),
                                      );
                                    }
                                  }
                                },
                        );
                      }).toList(),
                    ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancelButton),
          ),
        ],
      ),
    );
  }

  void _showDownloadDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final repoController = TextEditingController();
    final fileController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.downloadModelTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: 'huggingface',
                decoration: InputDecoration(
                  labelText: l10n.providerLabel,
                  border: const OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'huggingface', child: Text('Hugging Face')),
                ],
                onChanged: (_) {},
              ),
              const SizedBox(height: 12),
              TextField(
                controller: repoController,
                decoration: InputDecoration(
                  labelText: l10n.repoIdLabel,
                  hintText: l10n.repoIdHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fileController,
                decoration: InputDecoration(
                  labelText: l10n.fileNameLabel,
                  hintText: '${l10n.fileNameHint} (optional)',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () async {
              final repoId = repoController.text.trim();
              final filename = fileController.text.trim();
              if (repoId.isEmpty) return;

              Navigator.pop(ctx);
              try {
                await _api.downloadHfModel(repoId, filename.isNotEmpty ? filename : null);
                if (mounted) {
                  _handleRefresh();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.downloadQueued(repoId))),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.downloadFailed(e.toString()))),
                  );
                }
              }
            },
            child: Text(l10n.downloadAction),
          ),
        ],
      ),
    );
  }

  static void openModelDetailPage(BuildContext context, Map<String, dynamic> model) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ModelDetailPage(model: model)),
    );
  }

  static List<Widget> _buildConfigRows(AppLocalizations l10n, String configJson) {
    try {
      final config = jsonDecode(configJson) as Map<String, dynamic>;
      final widgets = <Widget>[
        const Divider(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(l10n.modelConfigLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ];
      config.forEach((key, value) {
        String displayValue;
        if (value is List) {
          displayValue = value.map((e) => e is Map ? e['rfilename'] ?? e.toString() : e.toString()).join(', ');
          if (displayValue.length > 120) {
            displayValue = '${displayValue.substring(0, 120)}...';
          }
        } else {
          displayValue = value.toString();
        }
        widgets.add(_detailRowStatic(key, displayValue));
      });
      return widgets;
    } catch (_) {
      return [];
    }
  }

  static Widget _detailRowStatic(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 200,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

}

class ModelDetailPage extends StatefulWidget {
  final Map<String, dynamic> model;

  const ModelDetailPage({super.key, required this.model});

  @override
  State<ModelDetailPage> createState() => _ModelDetailPageState();
}

class _ModelDetailPageState extends State<ModelDetailPage> {
  late Map<String, dynamic> _model;

  @override
  void initState() {
    super.initState();
    _model = widget.model;
    _pollIfDownloading();
  }

  void _pollIfDownloading() {
    if (_model['is_ready'] == true) return;

    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return false;
      try {
        final models = await ApiService().getLocalModels();
        final updated = models.cast<Map<String, dynamic>>().firstWhere(
          (m) => m['name'] == _model['name'],
          orElse: () => _model,
        );
        if (mounted) setState(() => _model = updated);
        return _model['is_ready'] != true && mounted;
      } catch (_) {
        return false;
      }
    });
  }

  bool get _isDownloading =>
      _model['is_ready'] != true && _model['downloaded_at'] == null;

  Future<void> _deleteModel() async {
    final l10n = AppLocalizations.of(context)!;
    final modelName = _model['name'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteModelLabel),
        content: Text(l10n.deleteModelConfirm(modelName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.deleteModelLabel)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final modelName = _model['name'] as String? ?? '';
      await ApiService().deleteModel(modelName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.modelDeleted)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _reDownload() async {
    final l10n = AppLocalizations.of(context)!;
    final repoId = _model['name'] as String? ?? '';
    try {
      final apiBase = _model['api_base'] as String? ?? '';
      final filename = _model['model_type'] == 'gguf' ? apiBase.split('/').last : null;
      await ApiService().downloadHfModel(repoId, filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.downloadQueued(repoId))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _isDownloading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.model_training, size: 20),
            const SizedBox(width: 8),
            Text(l10n.modelDetailTitle),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _deleteModel();
              if (value == 'redownload') _reDownload();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'redownload',
                child: Row(children: [
                  Icon(Icons.download, size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Text(l10n.reDownloadLabel, style: const TextStyle(fontSize: 13)),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                  const SizedBox(width: 8),
                  Text(l10n.deleteModelLabel, style: TextStyle(fontSize: 13, color: Colors.red.shade700)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AiConfigWidgetState._detailRowStatic(l10n.modelNameLabel, _model['name'] as String? ?? ''),
            _AiConfigWidgetState._detailRowStatic(l10n.modelProviderLabel, _model['provider'] as String? ?? ''),
            _AiConfigWidgetState._detailRowStatic(l10n.modelTypeLabel, _model['model_type'] as String? ?? ''),
            _AiConfigWidgetState._detailRowStatic(l10n.modelPathLabel, _model['api_base'] as String? ?? ''),
            _buildStatusRow(context),
            _AiConfigWidgetState._detailRowStatic(l10n.modelIsReadyLabel,
                _model['is_ready'] == true ? l10n.readyLabel : l10n.notReadyLabel),
            _AiConfigWidgetState._detailRowStatic(l10n.isLocalLabel,
                _model['is_local'] == true ? 'True' : 'False'),
            if (_model['total_size'] != null)
              _AiConfigWidgetState._detailRowStatic(l10n.modelTotalSizeLabel,
                  _model['current_total_size'] != null && _model['current_total_size'] != _model['total_size']
                      ? '${_formatFileSize(_model['current_total_size'])} / ${_formatFileSize(_model['total_size'])}'
                      : _formatFileSize(_model['total_size'])),
            if (_model['download_start_at'] != null)
              _AiConfigWidgetState._detailRowStatic(l10n.downloadStartLabel, _model['download_start_at'] as String),
            if (_model['downloaded_at'] != null)
              _AiConfigWidgetState._detailRowStatic(l10n.downloadedAtLabel, _model['downloaded_at'] as String),
            if (_model['created_at'] != null)
              _AiConfigWidgetState._detailRowStatic(l10n.createdLabel, _model['created_at'] as String),
            if (_model['updated_at'] != null)
              _AiConfigWidgetState._detailRowStatic(l10n.updatedLabel, _model['updated_at'] as String),
            if (_model['config'] != null) ..._AiConfigWidgetState._buildConfigRows(l10n, _model['config'] as String),
            if (_model['all_model_files'] != null) _buildModelFilesSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_isDownloading) {
      final progress = _AiConfigWidgetState._progressFromModel(_model);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: Text(l10n.modelStatusLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        progress != null ? '$progress%' : l10n.modelDownloadingStatus,
                        style: TextStyle(fontSize: 13, color: Colors.orange.shade700),
                      ),
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress / 100,
                      minHeight: 4,
                      backgroundColor: Colors.orange.shade100,
                      color: Colors.orange.shade700,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    return _AiConfigWidgetState._detailRowStatic(l10n.modelStatusLabel,
        _model['is_active'] == true ? l10n.activeLabel : l10n.inactiveLabel);
  }

  List<Map<String, dynamic>> _parseAllModelFiles(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => {'name': e, 'size': null}).cast<Map<String, dynamic>>().toList();
    }
    if (value is Map) {
      return value.entries.map((e) => {'name': e.key, 'size': e.value}).toList();
    }
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.map((e) => {'name': e, 'size': null}).cast<Map<String, dynamic>>().toList();
      }
      if (decoded is Map) {
        return decoded.entries.map((e) => {'name': e.key, 'size': e.value}).toList();
      }
    }
    return [];
  }

  static String _formatFileSize(dynamic bytes) {
    if (bytes == null || bytes == 0) return '';
    final size = bytes is int ? bytes : (bytes is double ? bytes.toInt() : int.tryParse(bytes.toString()) ?? 0);
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildModelFilesSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final files = _parseAllModelFiles(_model['all_model_files']);
    final currentFiles = _model['current_model_files'] as Map<String, dynamic>? ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(l10n.modelFilesLabel(files.length), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        ...files.map((f) {
          final fname = f['name'] as String;
          final expectedSize = f['size'];
          final currentSize = currentFiles[fname];
          final exists = currentSize != null;
          return Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Text(fname, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ),
                if (exists && expectedSize != null && expectedSize != 0)
                  Text(
                    '${_formatFileSize(currentSize)} / ${_formatFileSize(expectedSize)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  )
                else if (expectedSize != null && expectedSize != 0)
                  Text(
                    _formatFileSize(expectedSize),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                if (exists)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
