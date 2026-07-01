import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/models/nas_server.dart';

class MdnsDiscoveryWidget extends StatelessWidget {
  final List<NasServer> discoveredServers;
  final bool isScanning;
  final void Function(NasServer) onServiceSelected;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenBrowser;
  final String? currentTargetUrl;
  final String? serviceType;

  const MdnsDiscoveryWidget({
    super.key,
    required this.discoveredServers,
    required this.isScanning,
    required this.onServiceSelected,
    required this.onRefresh,
    this.onOpenBrowser,
    this.currentTargetUrl,
    this.serviceType,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (kIsWeb) {
      return Card(
        elevation: 2,
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.language, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(l10n.mdnsWebLimitationTitle, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.mdnsWebLimitationDesc,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.mdnsAvailableServers, style: Theme.of(context).textTheme.titleMedium),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onOpenBrowser != null)
                      IconButton(
                        icon: const Icon(Icons.open_in_full, size: 20),
                        onPressed: onOpenBrowser,
                        tooltip: l10n.mdnsBrowseAll,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    if (isScanning)
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh),
                  ],
                ),
              ],
            ),
            const Divider(),
            if (isScanning && discoveredServers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(
                      serviceType != null ? l10n.mdnsScanningForType(serviceType!) : l10n.mdnsScanningServers,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              )
            else if (discoveredServers.isEmpty && !isScanning)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text(l10n.mdnsNoServers)),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: discoveredServers.length,
                itemBuilder: (context, index) {
                  final server = discoveredServers[index];
                  final isTarget = currentTargetUrl != null && server.url == currentTargetUrl;
                  return ListTile(
                    leading: Icon(
                      isTarget ? Icons.check_circle : Icons.dns_outlined,
                      color: isTarget ? Colors.green : null,
                    ),
                    title: Text(
                      server.name,
                      style: isTarget ? const TextStyle(fontWeight: FontWeight.bold) : null,
                    ),
                    subtitle: Text(
                      server.displayUrl,
                      style: TextStyle(
                        fontSize: 12,
                        color: isTarget ? Colors.green : null,
                      ),
                    ),
                    trailing: Icon(isTarget ? Icons.check_circle : Icons.chevron_right,
                        color: isTarget ? Colors.green : null),
                    tileColor: isTarget ? Colors.green.withOpacity(0.08) : null,
                    shape: isTarget
                        ? RoundedRectangleBorder(
                            side: BorderSide(color: Colors.green.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(8),
                          )
                        : null,
                    onTap: () => onServiceSelected(server),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
