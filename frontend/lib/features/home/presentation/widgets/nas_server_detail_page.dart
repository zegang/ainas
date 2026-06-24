import 'package:flutter/material.dart';
import 'package:ainas_frontend/shared/models/nas_server.dart';
import 'package:ainas_frontend/services/api_service.dart';

class NasServerDetailPage extends StatelessWidget {
  final NasServer server;

  const NasServerDetailPage({super.key, required this.server});

  Future<void> _setAsTarget(BuildContext context) async {
    final api = ApiService();
    await api.persistBaseUrl(server.url);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Target AI NAS set to ${server.displayUrl}'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
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
              const PopupMenuItem(
                value: 'set_target',
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('Set as Target'),
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
                  _detailRow(Icons.dns, 'Name', server.name),
                  const Divider(),
                  _detailRow(Icons.link, 'Hostname', server.host),
                  const Divider(),
                  _detailRow(Icons.router, 'Port', server.port.toString()),
                  const Divider(),
                  _detailRow(Icons.low_priority, 'Priority', server.priority.toString()),
                  const Divider(),
                  _detailRow(Icons.swap_vert, 'Weight', server.weight.toString()),
                  if (server.addresses.isNotEmpty) ...[
                    const Divider(),
                    _detailRow(Icons.language, 'IPv4',
                        server.addresses.first),
                  ],
                  if (server.ipv6Addresses.isNotEmpty) ...[
                    const Divider(),
                    _detailRow(Icons.language, 'IPv6',
                        server.ipv6Addresses.first),
                  ],
                ],
              ),
              if (server.addresses.length > 1) ...[
                const SizedBox(height: 8),
                _detailCard(
                  context,
                  children: [
                    Text('Additional IPv4 Addresses',
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
                    Text('Additional IPv6 Addresses',
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
              if (server.txtRecords.isNotEmpty) ...[
                const SizedBox(height: 8),
                _detailCard(
                  context,
                  children: [
                    Text('TXT Records',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ...server.txtRecords.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(entry, style: const TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
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
                  label: const Text('Set as Target AI NAS'),
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
