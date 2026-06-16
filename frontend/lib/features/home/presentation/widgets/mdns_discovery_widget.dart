import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class MdnsDiscoveryWidget extends StatelessWidget {
  final List<String> discoveredServices;
  final bool isScanning;
  final Function(String) onServiceSelected;
  final VoidCallback onRefresh;

  const MdnsDiscoveryWidget({
    super.key,
    required this.discoveredServices,
    required this.isScanning,
    required this.onServiceSelected,
    required this.onRefresh,
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
              const SizedBox(height: 8),
              Text("Current Target: ${discoveredServices.isNotEmpty ? discoveredServices.first : 'Default'}", 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
            if (discoveredServices.isEmpty && !isScanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text("No servers found on local network")),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: discoveredServices.length,
                itemBuilder: (context, index) {
                  final service = discoveredServices[index];
                  return ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(service),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onServiceSelected(service),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}