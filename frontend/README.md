# ainas_frontend

[![Version](https://img.shields.io/badge/version-1.0.0-blue)](https://github.com/zegang/ainas/releases)
[![Dart SDK](https://img.shields.io/badge/dart-%3E%3D3.0.0-blue)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20android-3ddc84?logo=linux)](https://flutter.dev)
[![License](https://img.shields.io/github/license/zegang/ainas)](https://github.com/zegang/ainas/blob/main/LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/zegang/ainas?style=social)](https://github.com/zegang/ainas)

A Flutter-based GUI for the AI-NAS.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Internationalization (i18n)

This project uses the official Flutter localization tool.

1. **Configuration**: Managed via `l10n.yaml`.
2. **ARB Files**: Located in `lib/l10n/`. To add a new language, create `app_<locale>.arb`.
3. **Generation**: Ensure `generate: true` is set in `pubspec.yaml`. The `bootstrap.sh` script (or `flutter pub get`) will automatically generate the Dart localization classes.
4. **Usage**:
   Import the generated classes and configure your `MaterialApp`:

   ```dart
   import 'package:flutter_gen/gen_l10n/app_localizations.dart';

   return MaterialApp(
     localizationsDelegates: AppLocalizations.localizationsDelegates,
     supportedLocales: AppLocalizations.supportedLocales,
     onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
     // ...
   );
   ```

### Manual Language Switching

To switch languages manually (e.g., via a button), you need to manage the `Locale` state at the top of your application. A simple way is to use a `ValueNotifier`.

1. **Create a global or top-level notifier** (e.g., in `main.dart`):
   ```dart
   final localeNotifier = ValueNotifier<Locale?>(null); // null uses system default
   ```

2. **Wrap your MaterialApp** with `ValueListenableBuilder`:
   ```dart
   ValueListenableBuilder<Locale?>(
     valueListenable: localeNotifier,
     builder: (context, locale, _) {
       return MaterialApp(
         locale: locale,
         localizationsDelegates: AppLocalizations.localizationsDelegates,
         supportedLocales: AppLocalizations.supportedLocales,
         home: MyHomePage(),
       );
     },
   );
   ```

3. **Trigger the change using a Button**:
   ```dart
   ElevatedButton(
     onPressed: () {
       // Toggle between English and Chinese
       if (localeNotifier.value?.languageCode == 'zh') {
         localeNotifier.value = const Locale('en');
       } else {
         localeNotifier.value = const Locale('zh');
       }
     },
     child: Text(AppLocalizations.of(context)!.switchLanguage),
   )
   ```
