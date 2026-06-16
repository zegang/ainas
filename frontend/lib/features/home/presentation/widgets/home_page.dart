import 'package:flutter/material.dart';
import '../widgets/mdns_discovery_widget.dart';
import '../widgets/storage_dashboard_widget.dart';
import '../widgets/ai_config_widget.dart';
import '../../../../services/api_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _api = ApiService();
  bool _isScanning = false;
  List<String> _discoveredServers = [];
  Map<String, dynamic>? _storageUsage;
  Map<String, dynamic>? _aiConfig;
  Map<String, dynamic>? _ragStatus;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _isScanning = true);
    
    try {
      // Execute backend fetches in parallel for better performance
      final results = await Future.wait([
        _api.getSystemUsage(),
        _api.getAiConfig(),
        _api.getRagStatus(),
      ]);

      setState(() {
        _storageUsage = results[0];
        _aiConfig = results[1];
        _ragStatus = results[2];
        _discoveredServers = [_api.baseUrl.replaceAll(RegExp(r'https?://'), '')];
      });
    } catch (e) {
      debugPrint("Home Page Refresh Error: $e");
    } finally {
      setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI-NAS Home")),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          MdnsDiscoveryWidget(
            discoveredServices: _discoveredServers,
            isScanning: _isScanning,
            onRefresh: _refreshAll,
            onServiceSelected: (s) => print("Selected $s"),
          ),
          const SizedBox(height: 16),
          StorageDashboardWidget(
            usageData: _storageUsage,
            onRefresh: _refreshAll,
          ),
          const SizedBox(height: 16),
          AiConfigWidget(
            modelConfig: _aiConfig,
            ragStatus: _ragStatus,
            onRefresh: _refreshAll,
          ),
        ],
      ),
    );
  }
}