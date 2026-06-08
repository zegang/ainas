// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AI-NAS';

  @override
  String get navFiles => 'Files';

  @override
  String get navAiSearch => 'AI Search';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get refreshTooltip => 'Save and Refresh';

  @override
  String get searchHint => 'Search files or tags';

  @override
  String get fileUploaded => 'File uploaded successfully!';

  @override
  String get uploadLabel => 'Upload File';

  @override
  String get themeMode => 'Theme Mode';

  @override
  String get themeSystem => 'System Default';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get switchLanguage => 'Language';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get clear => 'Clear';

  @override
  String get newFolderTitle => 'New Folder';

  @override
  String get newFolderHint => 'Folder name';

  @override
  String get createButton => 'Create';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get selectFiles => 'Select Files';

  @override
  String selectButton(Object count) {
    return 'Select ($count)';
  }
}
