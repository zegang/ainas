import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'login_widget.dart';

class SettingsWidget extends StatefulWidget {
  const SettingsWidget({super.key});

  @override
  State<SettingsWidget> createState() => _SettingsWidgetState();
}

class _SettingsWidgetState extends State<SettingsWidget> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  final ApiService _api = ApiService();
  bool? _isConnected;
  bool _isChecking = false;
  late String _selectedLocale;
  late ThemeMode _selectedThemeMode;
  Timer? _debounceTimer;
  String? _hostError;
  String? _portError;
  bool _isAutoSaving = false;

  @override
  void initState() {
    super.initState();

    final uri = Uri.tryParse(_api.baseUrl) ?? Uri.parse("http://localhost:9026");

    // Use current settings from the singleton as the starting point
    final defaultHost = uri.host.isEmpty ? "localhost" : uri.host;
    final defaultPort = (uri.port == 0 || uri.port == 80) ? "9026" : uri.port.toString();
    
    _hostController = TextEditingController(text: defaultHost);
    _portController = TextEditingController(text: defaultPort);
    _selectedLocale = _api.locale;
    _selectedThemeMode = _api.themeMode;

    _hostController.addListener(_onSettingChanged);
    _portController.addListener(_onSettingChanged);
    _api.addListener(_handleApiChanged);
  }

  void _handleApiChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onSettingChanged() {
    final host = _hostController.text.trim();
    final portText = _portController.text.trim();
    final port = int.tryParse(portText);

    bool isValid = true;
    setState(() {
      if (host.isEmpty) {
        _hostError = "Host cannot be empty";
        isValid = false;
      } else {
        _hostError = null;
      }

      if (portText.isEmpty) {
        _portError = "Port cannot be empty";
        isValid = false;
      } else if (port == null || port < 1 || port > 65535) {
        _portError = "Invalid port (1-65535)";
        isValid = false;
      } else {
        _portError = null;
      }
    });

    _debounceTimer?.cancel();
    if (isValid) {
      _debounceTimer = Timer(const Duration(milliseconds: 1000), _autoSave);
    }
  }

  Future<void> _autoSave() async {
    if (!mounted) return;
    
    setState(() {
      _isAutoSaving = true;
      _isChecking = true;
    });
    
    final host = _hostController.text.trim();
    final port = _portController.text.trim();
    final newUrl = "http://$host:$port";
    final bool urlChanged = newUrl != _api.baseUrl;
    
    try {
      // Always persist local preferences immediately
      await _api.persistThemeMode(_selectedThemeMode);
      await _api.persistLocale(_selectedLocale);

      if (urlChanged) {
        // If the URL changed, verify it before persisting
        final isHealthy = await _api.checkStatus(newUrl);
        if (!mounted) return;
        
        if (isHealthy) {
          await _api.persistBaseUrl(newUrl);
          setState(() => _isConnected = true);
        } else {
          setState(() => _isConnected = false);
        }
      }
    } finally {
      // Small delay to ensure the "Saving..." message is actually visible to the user
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() => _isAutoSaving = false);
        setState(() => _isChecking = false);
      }
    }
  }

  Widget _buildStatusIcon() {
    if (_isChecking) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_isConnected == null) {
      return const Icon(Icons.help_outline, color: Colors.grey);
    }
    return Icon(
      _isConnected! ? Icons.check_circle : Icons.error,
      color: _isConnected! ? Colors.green : Colors.red,
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

  Future<bool> _ensureLoggedIn(BuildContext context) async {
    if (_api.isLoggedIn) {
      return true;
    }
    return await showLoginDialog(context);
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
                Text(
                  l10n.settingsTooltip,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _hostController,
                        decoration: InputDecoration(
                          labelText: "Server IP / Host",
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
                          labelText: "Port",
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
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text("English")),
                    DropdownMenuItem(value: 'zh', child: Text("中文")),
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
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_hostError != null || _portError != null || _isChecking)
                        ? null
                        : () async {
                      if (!await _ensureLoggedIn(context)) {
                        return;
                      }

                      final host = _hostController.text.trim();
                      final port = _portController.text.trim();
                      final newUrl = "http://$host:$port";
                      final bool urlChanged = newUrl != _api.baseUrl;
                      
                      // Only force a connectivity check if the server address was actually changed.
                      final isHealthy = urlChanged ? await _api.checkStatus(newUrl) : true;
                      if (!mounted) return;

                      // Always persist local preferences regardless of server connectivity.
                      await _api.persistThemeMode(_selectedThemeMode);
                      await _api.persistLocale(_selectedLocale);

                      if (urlChanged && !isHealthy) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Theme.of(context).colorScheme.error,
                            content: Text("Connection failed: Unable to reach $newUrl. Local settings saved."),
                          ),
                        );
                      } else {
                        if (urlChanged) {
                          await _api.persistBaseUrl(newUrl);
                        }
                        
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context, true);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Settings saved successfully!")),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.save),
                    label: Text(l10n.refreshTooltip),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                    onPressed: _api.isLoggedIn
                        ? () async {
                            await _api.logout();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.logoutSuccess),
                                backgroundColor: theme.colorScheme.background,
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.logout),
                    label: Text(l10n.logout),
                  ),
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
                        "Saving...",
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
