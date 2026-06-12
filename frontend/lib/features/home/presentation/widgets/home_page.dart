import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/services/mdns_service.dart';
import 'package:ainas_frontend/shared/models/nas_server.dart';

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

    try {
      await for (final server in MdnsService.scanForServers()) {
        if (!_discoveredServers.any((s) => s.url == server.url)) {
          setState(() => _discoveredServers.add(server));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Discovery error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _selectServer(NasServer server) async {
    final api = ApiService();
    if (server.url == api.baseUrl) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Switch Server'),
        content: Text('Do you want to switch to ${server.name} (${server.url})?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Connect'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await api.updateBaseUrl(server.url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to ${server.name}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = ApiService();

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
              final isSelected = server.url == api.baseUrl;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: isSelected
                    ? RoundedRectangleBorder(
                        side: BorderSide(color: theme.colorScheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(12))
                    : null,
                child: ListTile(
                  selected: isSelected,
                  leading: Icon(Icons.storage, 
                      color: isSelected ? theme.colorScheme.primary : Colors.blue),
                  title: Text(server.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(server.url),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                      : const Icon(Icons.power_settings_new),
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
