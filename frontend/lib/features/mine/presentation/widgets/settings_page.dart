import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  final ApiService _api = ApiService();
  bool? _isConnected;
  bool _isChecking = false;
  late String _selectedLocale;
  late ThemeMode _selectedThemeMode;
  late double _selectedFontScale;
  Timer? _debounceTimer;
  String? _hostError;
  String? _portError;
  bool _isAutoSaving = false;

  @override
  void initState() {
    super.initState();

    _hostController = TextEditingController(text: '');
    _portController = TextEditingController(text: '');
    _selectedLocale = _api.locale;
    _selectedThemeMode = _api.themeMode;
    _selectedFontScale = _api.fontScale;

    _hostController.addListener(_onSettingChanged);
    _portController.addListener(_onSettingChanged);
    _api.addListener(_handleApiChanged);
  }

  void _handleApiChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onSettingChanged() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final host = _hostController.text.trim();
    final portText = _portController.text.trim();
    final port = int.tryParse(portText);

    _debounceTimer?.cancel();

    if (host.isEmpty || portText.isEmpty) {
      setState(() {
        _hostError = null;
        _portError = null;
      });
      return;
    }

    setState(() {
      _hostError = null;
      if (port == null || port < 1 || port > 65535) {
        _portError = l10n.portInvalidError;
      } else {
        _portError = null;
      }
    });

    if (port != null && port >= 1 && port <= 65535) {
      _debounceTimer = Timer(const Duration(milliseconds: 1000), _autoSave);
    }
  }

  Future<void> _autoSave() async {
    if (!mounted) return;

    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _isAutoSaving = true;
    });

    final host = _hostController.text.trim();
    final port = _portController.text.trim();
    final hasAddress = host.isNotEmpty && port.isNotEmpty;
    final newUrl = hasAddress ? "http://$host:$port" : "";

    try {
      // Always persist local preferences immediately
      await _api.persistThemeMode(_selectedThemeMode);
      await _api.persistLocale(_selectedLocale);
      await _api.persistFontScale(_selectedFontScale);

      if (hasAddress && newUrl != _api.baseUrl) {
        await _api.persistBaseUrl(newUrl);
        if (!mounted) return;

        setState(() => _isChecking = true);

        final isHealthy = await _api.checkStatus(newUrl);
        if (!mounted) return;

        if (isHealthy) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.settingsSaved),
              backgroundColor: Colors.green,
            ),
          );
          setState(() => _isConnected = true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.connectionFailedLocalSaved(newUrl)),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          setState(() => _isConnected = false);
        }
        if (mounted) setState(() => _isChecking = false);
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() => _isAutoSaving = false);
      }
    }
  }

  Future<void> _checkConnection() async {
    final host = _hostController.text.trim();
    final port = _portController.text.trim();
    if (host.isEmpty || port.isEmpty) return;

    setState(() => _isChecking = true);
    final url = "http://$host:$port";
    final isHealthy = await _api.checkStatus(url);
    if (!mounted) return;
    setState(() {
      _isChecking = false;
      _isConnected = isHealthy;
    });
  }

  Widget _buildStatusIcon() {
    Widget icon;
    if (_isChecking) {
      icon = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_isConnected == null) {
      icon = const Icon(Icons.help_outline, color: Colors.grey);
    } else {
      icon = Icon(
        _isConnected! ? Icons.check_circle : Icons.error,
        color: _isConnected! ? Colors.green : Colors.red,
      );
    }

    return Tooltip(
      message: 'Check connection',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _isChecking ? null : _checkConnection,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: icon,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _debounceTimer?.cancel();
    _api.removeListener(_handleApiChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _hostController,
                        decoration: InputDecoration(
                          labelText: l10n.hostLabel,
                          border: const OutlineInputBorder(),
                          errorText: _hostError,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _portController,
                        decoration: InputDecoration(
                          labelText: l10n.portLabel,
                          border: const OutlineInputBorder(),
                          errorText: _portError,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: _buildStatusIcon(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedLocale,
                  decoration: InputDecoration(
                    labelText: l10n.switchLanguage,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
                    DropdownMenuItem(value: 'zh', child: Text(l10n.languageChinese)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedLocale = value);
                      _onSettingChanged();
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ThemeMode>(
                  value: _selectedThemeMode,
                  decoration: InputDecoration(
                    labelText: l10n.themeMode,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: ThemeMode.system, child: Text(l10n.themeSystem)),
                    DropdownMenuItem(value: ThemeMode.light, child: Text(l10n.themeLight)),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text(l10n.themeDark)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedThemeMode = value;
                      });
                      _onSettingChanged();
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<double>(
                  value: _selectedFontScale,
                  decoration: InputDecoration(
                    labelText: l10n.fontSize,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 0.85, child: Text(l10n.fontSizeSmall)),
                    DropdownMenuItem(value: 1.0, child: Text(l10n.fontSizeNormal)),
                    DropdownMenuItem(value: 1.15, child: Text(l10n.fontSizeLarge)),
                    DropdownMenuItem(value: 1.3, child: Text(l10n.fontSizeExtraLarge)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedFontScale = value);
                      _onSettingChanged();
                    }
                  },
                ),
              ],
            ),
        ),
        if (_isAutoSaving)
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.saving,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
