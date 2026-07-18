import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/services/lic_service.dart';
import 'package:ainas_frontend/features/mine/presentation/widgets/settings_page.dart';
import 'package:ainas_frontend/features/mine/presentation/widgets/storage_page.dart';
import 'package:ainas_frontend/features/mine/presentation/widgets/user_info_page.dart';
import 'package:ainas_frontend/features/mine/presentation/widgets/ai_config_page.dart';
import 'package:ainas_frontend/features/mine/presentation/widgets/version_page.dart';
import 'package:ainas_frontend/features/license/license_page.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  final _lic = LicService();
  bool _hasMultiuser = true;
  bool _hasAi = true;

  @override
  void initState() {
    super.initState();
    _checkFeatures();
    _lic.addListener(_onLicChanged);
  }

  @override
  void dispose() {
    _lic.removeListener(_onLicChanged);
    super.dispose();
  }

  void _onLicChanged() {
    _checkFeatures();
  }

  Future<void> _checkFeatures() async {
    final m = await _lic.hasFeature(LicService.featureMultiuser);
    final a = await _lic.hasFeature(LicService.featureAi);
    if (mounted) setState(() { _hasMultiuser = m; _hasAi = a; });
  }

  void _onAiScanPressed(BuildContext context) {
    if (!_hasAi) return;
    final api = ApiService();
    if (_hasMultiuser && !api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.aiScanLoginRequired)),
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
            child: Icon(
              _hasMultiuser ? Icons.person : Icons.person_off,
              color: Colors.white,
            ),
          ),
          onPressed: _hasMultiuser
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const UserInfoPage()),
                  )
              : null,
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
          if (_hasAi)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: l10n.aiScanTooltip,
              onPressed: () => _onAiScanPressed(context),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primaryContainer,
                      Theme.of(context).colorScheme.tertiaryContainer,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Icon(Icons.campaign, color: Theme.of(context).colorScheme.primary, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Sponsored',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Check out AI-NAS Pro for advanced features',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          minimumSize: const Size(0, 32),
                        ),
                        onPressed: () => launchUrl(Uri.parse('https://zegang.github.io/ainas/')),
                        child: const Text('Learn More', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Text(
                      l10n.settingServiceTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings),
                    title: Text(l10n.settingsTooltip),
                    subtitle: Text(l10n.settingsSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text(l10n.settingsTooltip)),
                          body: const SettingsPage(),
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.storage),
                    title: Text(l10n.storageTitle),
                    subtitle: Text(l10n.storageSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const StoragePage()),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.verified_user),
                    title: Text(l10n.licenseMenuTitle),
                    subtitle: Text(l10n.licenseMenuSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LicActivationPage()),
                    ),
                  ),
                  ListTile(
                    leading: Icon(_hasAi ? Icons.auto_awesome : Icons.lock_outline),
                    title: Text(l10n.aiTileTitle),
                    subtitle: Text(l10n.aiTileSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: _hasAi,
                    onTap: _hasAi
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AiConfigPage()),
                            )
                        : null,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(l10n.versionTitle),
                    subtitle: Text(l10n.versionSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const VersionPage()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
