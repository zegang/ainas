import 'dart:async';
import 'package:flutter/material.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../../../../services/api_service.dart';
import '../../domain/models/nas_server.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<NasServer> _discoveredServers = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _scanForServers();
  }

  Future<void> _scanForServers() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _discoveredServers.clear();
    });

    const String name = '_ainas._tcp.local';
    final MDNSClient client = MDNSClient();
    await client.start();

    try {
      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(name))) {
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName))) {
          
          final server = NasServer(
            name: ptr.domainName.split('.').first,
            host: srv.target,
            port: srv.port,
          );

          if (!_discoveredServers.any((s) => s.url == server.url)) {
            setState(() => _discoveredServers.add(server));
          }
        }
      }
    } finally {
      client.stop();
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _selectServer(NasServer server) async {
    final api = ApiService();
    // Assuming ApiService has a way to update the target host dynamically
    api.updateBaseUrl(server.url);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Connected to ${server.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NAS Discovery'),
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _scanForServers),
        ],
      ),
      body: _discoveredServers.isEmpty 
        ? _buildEmptyState(theme)
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _discoveredServers.length,
            itemBuilder: (context, index) {
              final server = _discoveredServers[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.storage, color: Colors.blue),
                  title: Text(server.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(server.url),
                  trailing: const Icon(Icons.power_settings_new),
                  onTap: () => _selectServer(server),
                ),
              );
            },
          ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.podcasts, size: 80, color: theme.disabledColor),
          const SizedBox(height: 16),
          Text(_isScanning ? 'Searching network...' : 'No AI-NAS servers found'),
        ],
      ),
    );
  }
}