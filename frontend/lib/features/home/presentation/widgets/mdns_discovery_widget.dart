import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ainas_frontend/shared/models/nas_server.dart';

class MdnsDiscoveryWidget extends StatelessWidget {
  final List<NasServer> discoveredServers;
  final bool isScanning;
  final void Function(NasServer) onServiceSelected;
  final VoidCallback onRefresh;
  final String? currentTargetUrl;

  const MdnsDiscoveryWidget({
    super.key,
    required this.discoveredServers,
    required this.isScanning,
    required this.onServiceSelected,
    required this.onRefresh,
    this.currentTargetUrl,
  });

  @override
  Widget build(BuildContext context) {
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
                  Text("Web Browser Limitation", style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "mDNS Service Discovery is not supported in web browsers due to security restrictions. "
                "Please ensure your NAS address is correctly configured in the app settings.",
                style: TextStyle(fontSize: 13),
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
                Text("Available AI NAS Servers", style: Theme.of(context).textTheme.titleMedium),
                if (isScanning)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh),
              ],
            ),
            const Divider(),
            if (discoveredServers.isEmpty && !isScanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text("No servers found on local network")),
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