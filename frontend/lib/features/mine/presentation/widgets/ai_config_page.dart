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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.errorLabel(_error!)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.retry),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
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
