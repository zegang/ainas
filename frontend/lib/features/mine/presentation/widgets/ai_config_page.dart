import 'package:flutter/material.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/widgets/ai_config_widget.dart';

class AiConfigPage extends StatefulWidget {
  const AiConfigPage({super.key});

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  final _api = ApiService();
  Map<String, dynamic>? _ragStatus;
  Map<String, dynamic>? _aiStatus;
  bool _loading = true;
  String? _error;

  Widget _buildStatusCard() {
    final l10n = AppLocalizations.of(context)!;
    final status = _aiStatus?['status'] as String? ?? 'unknown';
    final error = _aiStatus?['error'] as String?;
    final models = _aiStatus?['models_available'] as int? ?? 0;
    final pid = _aiStatus?['pid'] as int? ?? 0;
    final binary = _aiStatus?['binary'] as String? ?? '';
    final port = _aiStatus?['port'] as int? ?? 0;
    final modelsFolder = _aiStatus?['models_folder'] as String? ?? '';

    IconData icon;
    Color color;
    String label;
    switch (status) {
      case 'ready':
        icon = Icons.check_circle;
        color = Colors.green;
        label = l10n.aiStatusReady;
        break;
      case 'initializing':
        icon = Icons.sync;
        color = Colors.orange;
        label = l10n.aiStatusInitializing;
        break;
      case 'error':
        icon = Icons.error;
        color = Colors.red;
        label = l10n.aiStatusError;
        break;
      default:
        icon = Icons.disabled_by_default;
        color = Colors.grey;
        label = l10n.aiStatusDisabled;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(status, style: TextStyle(color: color)),
              ],
            ),
            const Divider(),
            _row(l10n.modelsAvailable, models.toString()),
            if (pid > 0) _row('PID', pid.toString()),
            if (port > 0) _row('Port', port.toString()),
            if (binary.isNotEmpty) _row('Binary', binary),
            if (modelsFolder.isNotEmpty) _row('Models Folder', modelsFolder),
            if (error != null && error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.errorLabel(error)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getRagStatus(),
        _api.getAiStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _ragStatus = results[0] as Map<String, dynamic>;
        _aiStatus = results[1] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiConfigTitle)),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Card(
                      margin: const EdgeInsets.all(32),
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              l10n.backendUnreachable,
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.backendUnreachableHint,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _loadData,
                              icon: const Icon(Icons.refresh),
                              label: Text(l10n.retry),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStatusCard(),
                      const SizedBox(height: 16),
                      AiConfigWidget(
                        ragStatus: _ragStatus,
                        aiStatus: _aiStatus,
                        onRefresh: _loadData,
                      ),
                    ],
                  ),
      ),
    );
  }

}
