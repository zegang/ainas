import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/shared/widgets/log_viewer_page.dart';

class VersionPage extends StatelessWidget {
  const VersionPage({super.key});

  Future<void> _openBackendLog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final path = await ApiService().getConfig('log_file');
      if (!context.mounted) return;
      Navigator.pop(context); // dismiss loading indicator
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LogViewerPage(logFileName: path ?? 'ainas_backend.log'),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.backendUnreachable)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.versionTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Text(
                      'AI-NAS',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ListTile(
                    title: Text('v1.0.0+1'),
                    subtitle: Text('App version'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Text(
                      l10n.logViewerTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(l10n.logViewerTitle),
                    subtitle: Text(l10n.logViewerSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LogViewerPage()),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(l10n.backendLogViewerTitle),
                    subtitle: Text(l10n.backendLogViewerSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openBackendLog(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
