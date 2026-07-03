import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'db_service.dart';

class SettingsService with ChangeNotifier {
  SettingsService._internal();

  static final SettingsService _instance = SettingsService._internal();

  factory SettingsService() => _instance;

  final _log = Logger('SettingsService');

  DbService _db = SharedPrefDbService();

  set dbService(DbService service) {
    _db = service;
  }

  String baseUrl = 'http://${const String.fromEnvironment('AINAS_ADDR', defaultValue: '127.0.0.1')}:${const String.fromEnvironment('AINAS_PORT', defaultValue: '9026')}';
  static const String _baseUrlKey = 'nas_base_url';
  static const String _localeKey = 'nas_locale';
  static const String _themeModeKey = 'nas_theme_mode';
  static const String _fontScaleKey = 'nas_font_scale';

  String locale = 'zh';
  ThemeMode themeMode = ThemeMode.system;
  double fontScale = 1.0;

  Future<void> updateBaseUrl(String url) async {
    _log.info('To update base URL from $baseUrl to $url');
    baseUrl = url;
    persistBaseUrl(baseUrl);
  }

  Future<void> persistBaseUrl(String url) async {
    await _db.setString(_baseUrlKey, url);
    baseUrl = url;
    notifyListeners();
    _log.info('Persisted new base URL: $url');
  }

  Future<void> persistLocale(String langCode) async {
    await _db.setString(_localeKey, langCode);
    locale = langCode;
    notifyListeners();
    _log.info('Persisted new locale: $langCode');
  }

  Future<void> persistThemeMode(ThemeMode mode) async {
    await _db.setString(_themeModeKey, mode.name);
    themeMode = mode;
    notifyListeners();
    _log.info('Persisted new theme mode: $mode');
  }

  Future<void> persistFontScale(double scale) async {
    await _db.setDouble(_fontScaleKey, scale);
    fontScale = scale;
    notifyListeners();
    _log.info('Persisted font scale: $scale');
  }

  Future<void> loadSettings() async {
    baseUrl = (await _db.getString(_baseUrlKey)) ?? baseUrl;
    locale = (await _db.getString(_localeKey)) ?? locale;
    final savedThemeMode = await _db.getString(_themeModeKey);
    if (savedThemeMode != null) {
      themeMode = ThemeMode.values.firstWhere(
        (e) => e.name == savedThemeMode,
        orElse: () => ThemeMode.system,
      );
    }
    fontScale = (await _db.getDouble(_fontScaleKey)) ?? 1.0;
    notifyListeners();
    _log.info('Loaded base URL: $baseUrl');
  }
}
