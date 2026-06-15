import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:developer' as developer;
import 'l10n/app_localizations.dart';
import 'features/file_browser/presentation/widgets/nas_browser_page.dart';
import 'features/settings/presentation/widgets/settings_page.dart';
import './services/api_service.dart';
import 'shared/themes/app_theme.dart';
import 'features/home/presentation/widgets/home_page.dart';
import 'features/ai_assistant/presentation/widgets/ai_assistant_page.dart';

void main() async {
  _setupLogging();
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize the singleton and load saved settings
  final api = ApiService();
  await api.loadSettings();
  runApp(
    ListenableBuilder(
      listenable: api,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          // Use centralized themes
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          // Use the themeMode from ApiService
          themeMode: api.themeMode,
          // Use the locale from ApiService
          locale: Locale(api.locale),
          // Localization delegates
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MainShell(),
        );
      },
    ),
  );
}

void _setupLogging() {
  // Set the root level (usually Level.INFO for production, Level.ALL for debug)
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // Pass logs to dart:developer for structured viewing in DevTools
    developer.log(
      record.message,
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });

  // Append logs to a local file if running on a native platform (Linux/Android)
  if (!kIsWeb) {
    final logFile = File('../logs/ainas_frontend.log');
    Logger.root.onRecord.listen((record) {
      final sb = StringBuffer();
      sb.writeln('${record.time} [${record.level.name}] ${record.loggerName}: ${record.message}');
      if (record.error != null) {
        sb.writeln('Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        sb.writeln('StackTrace:\n${record.stackTrace}');
      }
      logFile.writeAsStringSync(sb.toString(), mode: FileMode.append, flush: true);
    });
  }
}

/// A shell widget that provides the primary industrial sidebar layout.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  Timer? _statusSyncTimer;

  @override
  void initState() {
    super.initState();
    // Perform an immediate sync on startup
    _syncNasStatus();
    // Schedule periodic sync every 30 seconds to update storage usage and connection state
    _statusSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _syncNasStatus(),
    );
  }

  @override
  void dispose() {
    _statusSyncTimer?.cancel();
    super.dispose();
  }

  void _syncNasStatus() => ApiService().checkStatus();

  String _getAiStatusLabel(String status) {
    switch (status) {
      case 'ready':
        return "AI Ready";
      case 'initializing':
        return "AI Not Ready - Initializing";
      case 'disabled':
        return "AI Disabled";
      default:
        return "AI Enabled";
    }
  }

  String _getAiStatusTooltip(String status) {
    switch (status) {
      case 'ready':
        return "The AI system is fully operational and ready to process your files.";
      case 'initializing':
        return "The AI engine is currently loading neural models. This usually takes 30-60 seconds depending on server hardware.";
      case 'disabled':
        return "AI features are currently turned off in the backend configuration or the necessary models are missing.";
      default:
        return "The AI system is active but its full capabilities are still being verified.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final api = ApiService();
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Breakpoint based on the widget's available width instead of screen size.
        final bool isMobile = constraints.maxWidth < 600;

        final appBar = AppBar(
          title: Row(
            children: [
              const Icon(Icons.dns, size: 28, color: Colors.blue),
              const SizedBox(width: 12),
              Text(l10n.appTitle),
            ],
          ),
          actions: [
            // AI Status Widget
            if (api.isServerConnected && !isMobile) ...[
              Tooltip(
                message: _getAiStatusTooltip(api.aiStatus),
                child: Row(
                  children: [
                    Icon(
                      api.aiStatus == 'ready' ? Icons.auto_awesome : Icons.psychology,
                      size: 16,
                      color: api.aiStatus == 'ready' 
                          ? themeExt.successColor 
                          : (api.aiStatus == 'initializing' ? Colors.orange : Colors.grey),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getAiStatusLabel(api.aiStatus),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
            ],
            // Storage Usage Widget
            if (!isMobile) ...[
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(api.storageLabel, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      value: api.storagePercent,
                    backgroundColor: themeExt.storageTrackColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
            ],
            // Connection Status Widget
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: api.isServerConnected ? themeExt.successColor : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(api.isServerConnected ? "Connected" : "Offline"),
              ],
            ),
            const SizedBox(width: 16),
          ],
        );

        final offlineBanner = api.isServerConnected
            ? null
            : _PulseBanner(onRetry: () => api.checkStatus());

        if (isMobile) {
          return Scaffold(
            appBar: appBar,
            body: Column(
              children: [
                if (offlineBanner != null) offlineBanner,
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeInOut,
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: l10n.homePage,
            ),
            NavigationDestination(
              icon: const Icon(Icons.folder_outlined),
              selectedIcon: const Icon(Icons.folder),
              label: l10n.navFiles,
            ),
            NavigationDestination(
              icon: const Icon(Icons.psychology_outlined),
              selectedIcon: const Icon(Icons.psychology),
              label: l10n.aiAssistant,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: l10n.settingsTooltip,
            ),
          ],
        ),
        );
        }

        return Scaffold(
          appBar: appBar,
          body: Row(
            children: [
              NavigationRail(
                extended: true,
                minExtendedWidth: 200,
                selectedIndex: _selectedIndex,
                onDestinationSelected: (int index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                destinations: [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: Text(l10n.homePage),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.folder_outlined),
                    selectedIcon: const Icon(Icons.folder),
                    label: Text(l10n.navFiles),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.psychology_outlined),
                    selectedIcon: const Icon(Icons.psychology),
                    label: Text(l10n.aiAssistant),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: const Icon(Icons.settings),
                    label: Text(l10n.settingsTooltip),
                  ),
                ],
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeInOut,
                  child: _buildBody(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const HomePage(key: ValueKey(0));
      case 1:
        return const NASBrowser(key: ValueKey(1));
      case 2:
        return const AIAssistantPage(key: ValueKey(2));
      case 3:
        return const SettingsPage(key: ValueKey(3));
      default:
        return const HomePage(key: ValueKey(0));
    }
  }
}

class _PulseBanner extends StatefulWidget {
  final VoidCallback onRetry;

  const _PulseBanner({required this.onRetry});

  @override
  State<_PulseBanner> createState() => _PulseBannerState();
}

class _PulseBannerState extends State<_PulseBanner> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200), // Slightly faster for a more active pulse
    )..repeat(reverse: true);
    _opacityAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.98, end: 1.0).animate( // Subtle scale change
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: MaterialBanner(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.onErrorContainer),
          content: Text(
            "Offline: Unable to connect to NAS server",
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          actions: [
            TextButton(
              onPressed: widget.onRetry,
              child: const Text("RETRY"),
            ),
          ]
          ),
        ),
      );
  }
}
