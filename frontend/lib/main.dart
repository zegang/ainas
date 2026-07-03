import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:developer' as developer;
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'l10n/app_localizations.dart';
import 'shared/utils/backend_process_manager.dart';
import 'features/file_browser/presentation/widgets/nas_browser_page.dart';
import 'features/mine/presentation/widgets/login_widget.dart';
import 'features/mine/presentation/widgets/mine_page.dart';
import 'features/mine/presentation/widgets/storage_page.dart';
import 'features/mine/presentation/widgets/ai_config_page.dart';
import './services/api_service.dart';
import 'shared/themes/app_theme.dart';
import 'shared/widgets/ad_splash_screen.dart';
import 'features/home/presentation/widgets/home_page.dart';
import 'features/ai_assistant/presentation/widgets/ai_assistant_page.dart';

void main() async {
  _setupLogging();
  WidgetsFlutterBinding.ensureInitialized();

  if (BackendProcessManager.isDesktopSupported) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
  }

  // Initialize the singleton and load saved settings
  final api = ApiService();
  await api.loadSettings();
  api.loadPendingUploads();
  runApp(
    ListenableBuilder(
      listenable: api,
      builder: (context, _) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaleFactor: api.fontScale),
          child: MaterialApp(
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
            home: AdSplashScreen(
              duration: const Duration(milliseconds: 3000),
              child: const MainShell(),
            ),
          ),
        );
      },
    ),
  );
}

void _setupLogging() {
  // Set the root level (usually Level.INFO for production, Level.ALL for debug)
  Logger.root.level = Level.ALL;

  // Append logs to a local file if running on a native platform (Linux/Android)
  if (!kIsWeb) {
    final logFile = File('ainas_frontend.log');
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
  } else {
      Logger.root.onRecord.listen((record) {
      print('${record.time} [${record.level.name}] ${record.loggerName}: ${record.message}');
      if (record.error != null) {
        print('Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        print('StackTrace:\n${record.stackTrace}');
      }
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
  }
}

/// A shell widget that provides the primary industrial sidebar layout.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WindowListener, TrayListener {
  Timer? _statusSyncTimer;
  bool _navRailExtended = true;

  @override
  void initState() {
    super.initState();
    if (BackendProcessManager.isDesktopSupported) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _setupTray();
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateTrayMenu());
    }
    // Perform an immediate sync on startup
    _syncNasStatus();
    // Schedule periodic sync every 30 seconds to update storage usage and connection state
    _statusSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _syncNasStatus(),
    );
  }

  Future<void> _setupTray() async {
    try {
      final ext = Platform.isWindows ? 'ico' : 'png';
      final assetPath = 'assets/tray_icon.$ext';
      final byteData = await rootBundle.load(assetPath);
      final tempDir = Directory.systemTemp;
      final iconFile = File('${tempDir.path}/ainas_tray_icon.$ext');
      await iconFile.writeAsBytes(byteData.buffer.asUint8List());
      await trayManager.setIcon(iconFile.path);
      await trayManager.setToolTip('AI-NAS');
      // Menu will be set with localized text after first build
      _updateTrayMenu();
    } catch (e) {
      developer.log('Tray setup failed: $e');
    }
  }

  void _updateTrayMenu() {
    final l10n = context.mounted ? AppLocalizations.of(context) : null;
    trayManager.setContextMenu(Menu(
      items: [
        MenuItem(key: 'show', label: l10n?.showWindow ?? 'Show Window'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: l10n?.quitApp ?? 'Quit'),
      ],
    ));
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'show':
        windowManager.show();
        break;
      case 'quit':
        _handleQuit();
        break;
    }
  }

  Future<void> _handleQuit() async {
    if (!context.mounted) return;
    final pids = await BackendProcessManager.listPids();
    if (pids.isNotEmpty && context.mounted) {
      await windowManager.show();
      final l10n = AppLocalizations.of(context)!;
      final stopBackend = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.quitApp),
          content: Text(l10n.quitBackendRunning),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelButton)),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.stop)),
          ],
        ),
      );
      if (stopBackend == true) {
        for (final pid in pids) {
          await BackendProcessManager.stopProcess(pid);
        }
      }
    }
    if (context.mounted) {
      await windowManager.destroy();
    }
    exit(0);
  }

  @override
  void dispose() {
    _statusSyncTimer?.cancel();
    if (BackendProcessManager.isDesktopSupported) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  void _syncNasStatus() => ApiService().checkStatus();

  Future<bool> _ensureLoggedIn(BuildContext context) async {
    final api = ApiService();
    if (api.isLoggedIn) {
      return true;
    }
    return await showLoginDialog(context);
  }

  String _getAiStatusLabel(String status, AppLocalizations l10n) {
    switch (status) {
      case 'ready':
        return l10n.aiStatusReady;
      case 'initializing':
        return l10n.aiStatusInitializing;
      case 'disabled':
        return l10n.aiStatusDisabled;
      default:
        return l10n.aiStatusEnabled;
    }
  }

  String _getAiStatusTooltip(String status, AppLocalizations l10n) {
    switch (status) {
      case 'ready':
        return l10n.aiStatusTooltipReady;
      case 'initializing':
        return l10n.aiStatusTooltipInitializing;
      case 'disabled':
        return l10n.aiStatusTooltipDisabled;
      default:
        return l10n.aiStatusTooltipEnabled;
    }
  }

  String? _getCriticalMessage(AppLocalizations l10n) {
    final api = ApiService();
    if (!api.isServerConnected) return null;
    if (api.aiStatus == 'initializing') return l10n.aiStatusTooltipInitializing;
    if (api.aiStatus == 'disabled') return l10n.aiStatusTooltipDisabled;
    return null;
  }

  Widget? _buildStatusBar(AppLocalizations l10n) {
    final msg = _getCriticalMessage(l10n);
    if (msg == null) return null;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.tertiaryContainer,
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg, style: TextStyle(fontSize: 12, color: theme.colorScheme.onTertiaryContainer)),
          ),
        ],
      ),
    );
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
          title: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [Colors.cyan, Colors.blue, Colors.purple],
            ).createShader(bounds),
            child: Text(
              l10n.appTitle,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 6.0,
                fontSize: 30,
                color: Colors.white,
              ),
            ),
          ),
          actions: [
            // AI Status Widget
            if (api.isServerConnected) ...[
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AiConfigPage()),
                ),
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
                      _getAiStatusLabel(api.aiStatus, l10n),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
            ],
            // Storage Usage Widget
            if (!isMobile) ...[
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StoragePage()),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(api.storageLabel.isEmpty ? l10n.loadingLabel : api.storageLabel, style: Theme.of(context).textTheme.labelSmall),
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
              ),
              const SizedBox(width: 16),
            ],
            // Connection Status Widget
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StoragePage()),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 12,
                    color: api.isServerConnected ? themeExt.successColor : Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Text(api.isServerConnected ? l10n.connected : l10n.offline),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
        );

        final offlineBanner = api.isServerConnected
            ? null
            : _PulseBanner(onRetry: () => api.checkStatus());
        final statusBar = _buildStatusBar(l10n);

        if (isMobile) {
          return Scaffold(
            appBar: appBar,
            body: Column(
              children: [
                if (offlineBanner != null) offlineBanner,
                if (statusBar != null) statusBar,
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
              selectedIndex: api.currentTabIndex,
              onDestinationSelected: (int index) {
                _ensureLoggedIn(context).then((loggedIn) {
                  if (loggedIn) api.setTabIndex(index);
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
                  icon: const Icon(Icons.auto_awesome, size: 28),
                  selectedIcon: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, size: 28),
                  ),
                  label: l10n.aiAssistant,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person),
                  label: l10n.minePage,
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: appBar,
          body: Column(
            children: [
              if (statusBar != null) statusBar,
              Expanded(
                child: Row(
                  children: [
                    NavigationRail(
                      extended: _navRailExtended,
                      minExtendedWidth: 200,
                      selectedIndex: api.currentTabIndex,
                      onDestinationSelected: (int index) {
                        _ensureLoggedIn(context).then((loggedIn) {
                          if (loggedIn) api.setTabIndex(index);
                        });
                      },
                      leading: Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 8),
                        child: IconButton(
                          icon: Icon(_navRailExtended ? Icons.menu_open : Icons.menu),
                          onPressed: () => setState(() => _navRailExtended = !_navRailExtended),
                          tooltip: _navRailExtended ? 'Collapse sidebar' : 'Expand sidebar',
                        ),
                      ),
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
                          icon: const Icon(Icons.person_outlined),
                          selectedIcon: const Icon(Icons.person),
                          label: Text(l10n.minePage),
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
                )
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    final api = ApiService();
    switch (api.currentTabIndex) {
      case 0:
        return const HomePage(key: ValueKey(0));
      case 1:
        return const NASBrowser(key: ValueKey(1));
      case 2:
        return const AIAssistantPage(key: ValueKey(2));
      case 3:
        return const MinePage(key: ValueKey(3));
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
    final l10n = AppLocalizations.of(context)!;
    return ScaleTransition(
      scale: _scaleAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: MaterialBanner(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.onErrorContainer),
          content: Text(
            l10n.offlineBannerMessage,
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          actions: [
            TextButton(
              onPressed: widget.onRetry,
              child: Text(l10n.retry),
            ),
          ]
        ),
      )
    );
  }
}
