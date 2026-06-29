import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/features/home/presentation/widgets/storage_dashboard_widget.dart';

class StorageMobilePage extends StatefulWidget {
  const StorageMobilePage({super.key});

  @override
  State<StorageMobilePage> createState() => _StorageMobilePageState();
}

class _StorageMobilePageState extends State<StorageMobilePage> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _usageData;
  String _storageRoot = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getSystemUsage(),
        _api.getSystemConfig(),
      ]);
      final usage = results[0];
      final config = results[1];
      final root = config['storage_root'] as String? ?? '';
      if (mounted) {
        setState(() {
          _usageData = usage;
          _storageRoot = root;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.storageTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildDiskUsageCard(l10n),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.storageRootPath,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.folder, size: 20,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _storageRoot.isNotEmpty
                                    ? _storageRoot
                                    : l10n.notConfigured,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDiskUsageCard(AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.storageTitle,
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _fetchData,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _usageData != null
                ? StorageDashboardWidget(usageData: _usageData)
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l10n.unavailable)),
                  ),
          ],
        ),
      ),
    );
  }
}
