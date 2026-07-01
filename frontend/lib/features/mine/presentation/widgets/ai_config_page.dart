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
  bool _toggling = false;
  String? _error;

  bool get _isAiEnabled {
    final status = _aiStatus?['status'] as String?;
    return status != 'disabled' && status != 'unknown' && status != null;
  }

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

  Widget _buildToggleSection() {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: _toggling
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isAiEnabled ? l10n.aiDisablingProgress : l10n.aiEnablingProgress,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isAiEnabled ? l10n.aiDisableHint : l10n.aiEnableHint,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : SwitchListTile(
              secondary: Icon(_isAiEnabled ? Icons.power_settings_new : Icons.power_off),
              title: Text(_isAiEnabled ? l10n.aiDisableTitle : l10n.aiEnableTitle),
              subtitle: Text(_isAiEnabled ? l10n.aiDisableHint : l10n.aiEnableHint),
              value: _isAiEnabled,
              onChanged: _onToggleAi,
            ),
    );
  }

  Future<void> _onToggleAi(bool enable) async {
    setState(() => _toggling = true);
    try {
      Map<String, dynamic> result;
      if (enable) {
        result = await _api.enableAi();
      } else {
        result = await _api.disableAi();
      }
      if (!mounted) return;
      final success = result['success'] == true;
      final message = result['message'] as String? ?? (success ? 'Done' : 'Failed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _toggling = false);
    await _loadData();
  }

  Future<void> _loadData({bool isRefresh = false}) async {
    if (!isRefresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
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
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (isRefresh) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      } else {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
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
        onRefresh: () => _loadData(isRefresh: true),
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
                      _buildToggleSection(),
                      const SizedBox(height: 16),
                      _buildStatusCard(),
                      if (_isAiEnabled) ...[
                        const SizedBox(height: 16),
                        AiConfigWidget(
                          ragStatus: _ragStatus,
                          aiStatus: _aiStatus,
                          onRefresh: () => _loadData(isRefresh: true),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }

}
