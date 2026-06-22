import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/features/mine/presentation/widgets/settings_widget.dart';
import 'package:ainas_frontend/features/mine/presentation/widgets/user_info_widget.dart';
import 'package:ainas_frontend/services/api_service.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  void _onAiScanPressed(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final api = ApiService();
    if (!api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiScanLoginRequired)),
      );
      return;
    }
    api.setTabIndex(2);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final api = ApiService();
    final username = api.username.isNotEmpty ? api.username : l10n.guestUser;
    final vipState = api.vipStatus;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          padding: const EdgeInsets.only(left: 12.0),
          icon: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(Icons.person, color: Colors.white),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const UserInfoPage()),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(username, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(vipState, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: l10n.aiScanTooltip,
            onPressed: () => _onAiScanPressed(context),
          ),
        ],
      ),
      body: const SettingsWidget(),
    );
  }
}
