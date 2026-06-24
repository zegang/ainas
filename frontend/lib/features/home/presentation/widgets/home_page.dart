import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ainas_frontend/features/home/presentation/widgets/mdns_discovery_widget.dart';
import 'package:ainas_frontend/features/home/presentation/widgets/nas_server_detail_page.dart';
import 'package:ainas_frontend/features/home/presentation/widgets/storage_dashboard_widget.dart';
import 'package:ainas_frontend/shared/widgets/ai_config_widget.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/services/mdns_service.dart';
import 'package:ainas_frontend/shared/models/nas_server.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _api = ApiService();
  bool _isScanning = false;
  List<NasServer> _discoveredServers = [];
  StreamSubscription<NasServer>? _mdnsSubscription;
  Map<String, dynamic>? _storageUsage;
  Map<String, dynamic>? _ragStatus;
  Map<String, dynamic>? _aiStatus;

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _startMdnsScan();
  }

  @override
  void dispose() {
    _mdnsSubscription?.cancel();
    super.dispose();
  }

  void _startMdnsScan() {
    if (kIsWeb) return;
    _mdnsSubscription?.cancel();
    _mdnsSubscription = MdnsService.scanForServers().listen((server) {
      if (!mounted) return;
      setState(() {
        _discoveredServers.removeWhere(
          (s) => s.host == server.host && s.port == server.port,
        );
        _discoveredServers.add(server);
      });
    });
  }

  Future<void> _refreshAll() async {
    setState(() => _isScanning = true);

    try {
      final results = await Future.wait([
        _api.getSystemUsage(),
        _api.getRagStatus(),
        _api.getAiStatus(),
      ]);

      setState(() {
        _storageUsage = results[0] as Map<String, dynamic>?;
        _ragStatus = results[1] as Map<String, dynamic>?;
        _aiStatus = results[2] as Map<String, dynamic>;
      });
    } catch (e) {
      debugPrint("Home Page Refresh Error: $e");
    } finally {
      setState(() => _isScanning = false);
    }
  }

  void _onServiceSelected(NasServer server) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NasServerDetailPage(server: server),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI-NAS Home")),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          MdnsDiscoveryWidget(
            discoveredServers: _discoveredServers,
            isScanning: _isScanning,
            onRefresh: _refreshAll,
            onServiceSelected: _onServiceSelected,
            currentTargetUrl: _api.baseUrl,
          ),
          const SizedBox(height: 16),
          StorageDashboardWidget(
            usageData: _storageUsage,
            onRefresh: _refreshAll,
          ),
          const SizedBox(height: 16),
          AiConfigWidget(
            ragStatus: _ragStatus,
            aiStatus: _aiStatus,
            onRefresh: _refreshAll,
            showLocalModelCard: false,
            showFeatureIcons: false,
            showRagDetails: false,
          ),
        ],
      ),
    );
  }
}