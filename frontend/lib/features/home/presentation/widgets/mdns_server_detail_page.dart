import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/models/nas_server.dart';
import 'package:ainas_frontend/services/api_service.dart';

class MdnsServerDetailPage extends StatelessWidget {
  final NasServer server;

  const MdnsServerDetailPage({super.key, required this.server});

  Future<void> _setAsTarget(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final api = ApiService();
    await api.persistBaseUrl(server.url);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.mdnsTargetSet(server.displayUrl)),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(server.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'set_target') {
                _setAsTarget(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'set_target',
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(l10n.mdnsSetAsTarget),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailCard(
                context,
                children: [
                  _detailRow(Icons.dns, l10n.mdnsNameLabel, server.name),
                  const Divider(),
                  _detailRow(Icons.link, l10n.mdnsHostnameLabel, server.host),
                  const Divider(),
                  _detailRow(Icons.router, l10n.portLabel, server.port.toString()),
                  const Divider(),
                  _detailRow(Icons.category, l10n.mdnsServiceTypeLabel, server.serviceType),
                  const Divider(),
                  _detailRow(Icons.low_priority, l10n.mdnsPriorityLabel, server.priority.toString()),
                  const Divider(),
                  _detailRow(Icons.swap_vert, l10n.mdnsWeightLabel, server.weight.toString()),
                  if (server.addresses.isNotEmpty) ...[
                    const Divider(),
                    _detailRow(Icons.language, l10n.mdnsIpv4Label,
                        server.addresses.first),
                  ],
                  if (server.ipv6Addresses.isNotEmpty) ...[
                    const Divider(),
                    _detailRow(Icons.language, l10n.mdnsIpv6Label,
                        server.ipv6Addresses.first),
                  ],
                ],
              ),
              if (server.addresses.length > 1) ...[
                const SizedBox(height: 8),
                _detailCard(
                  context,
                  children: [
                    Text(l10n.mdnsAdditionalIpv4,
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ...server.addresses.skip(1).map(
                      (addr) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.language, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(addr, style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (server.ipv6Addresses.length > 1) ...[
                const SizedBox(height: 8),
                _detailCard(
                  context,
                  children: [
                    Text(l10n.mdnsAdditionalIpv6,
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ...server.ipv6Addresses.skip(1).map(
                      (addr) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.language, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(addr, style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (server.properties.isNotEmpty) ...[
                const SizedBox(height: 8),
                _detailCard(
                  context,
                  children: [
                    Text(l10n.mdnsTxtRecords,
                        style: theme.textTheme.titleSmall),
                    ...server.properties.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _detailRow(Icons.info_outline, e.key, e.value),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _setAsTarget(context),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(l10n.mdnsSetAsTargetButton),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailCard(BuildContext context, {required List<Widget> children}) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
