import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/features/home/presentation/widgets/mdns_discovery_widget.dart';
import 'package:ainas_frontend/features/home/presentation/widgets/mdns_browser_page.dart';
import 'package:ainas_frontend/features/home/presentation/widgets/storage_dashboard_widget.dart';
import 'package:ainas_frontend/features/mine/presentation/widgets/storage_page.dart';
import 'package:ainas_frontend/services/api_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _storageUsage;

  @override
  void initState() {
    super.initState();
    _refreshStorageUsage();
  }

  Future<void> _refreshStorageUsage() async {
    try {
      final usage = await _api.getSystemUsage();
      setState(() => _storageUsage = usage as Map<String, dynamic>?);
    } catch (e) {
      debugPrint("Home Page Refresh Error: $e");
      setState(() => _storageUsage = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.homePageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          MdnsDiscoveryWidget(
            currentTargetUrl: _api.baseUrl,
            onRefresh: _refreshStorageUsage,
            onOpenBrowser: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MdnsBrowserPage()),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StoragePage()),
            ),
            child: StorageDashboardWidget(
              usageData: _storageUsage,
              onRefresh: _refreshStorageUsage,
            ),
          ),
        ],
      ),
    );
  }
}
