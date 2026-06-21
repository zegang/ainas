import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'AI-NAS'**
  String get appTitle;

  /// No description provided for @navFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get navFiles;

  /// No description provided for @navAiSearch.
  ///
  /// In en, this message translates to:
  /// **'AI Search'**
  String get navAiSearch;

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @refreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save and Refresh'**
  String get refreshTooltip;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search files or tags'**
  String get searchHint;

  /// No description provided for @fileUploaded.
  ///
  /// In en, this message translates to:
  /// **'File uploaded successfully!'**
  String get fileUploaded;

  /// No description provided for @uploadLabel.
  ///
  /// In en, this message translates to:
  /// **'Upload File'**
  String get uploadLabel;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get themeMode;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @switchLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get switchLanguage;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get testConnection;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @newFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolderTitle;

  /// No description provided for @newFolderHint.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get newFolderHint;

  /// No description provided for @createButton.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createButton;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @selectFiles.
  ///
  /// In en, this message translates to:
  /// **'Select Files'**
  String get selectFiles;

  /// No description provided for @selectButton.
  ///
  /// In en, this message translates to:
  /// **'Select ({count})'**
  String selectButton(Object count);

  /// No description provided for @homePage.
  ///
  /// In en, this message translates to:
  /// **'Home Page'**
  String get homePage;

  /// No description provided for @minePage.
  ///
  /// In en, this message translates to:
  /// **'Mine'**
  String get minePage;

  /// No description provided for @aiAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistant;

  /// No description provided for @aiTags.
  ///
  /// In en, this message translates to:
  /// **'AI Tags'**
  String get aiTags;

  /// No description provided for @aiToolName.
  ///
  /// In en, this message translates to:
  /// **'AI Tool'**
  String get aiToolName;

  /// No description provided for @thinkingProcess.
  ///
  /// In en, this message translates to:
  /// **'Thinking Process'**
  String get thinkingProcess;

  /// No description provided for @thinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking...'**
  String get thinking;

  /// No description provided for @toolResult.
  ///
  /// In en, this message translates to:
  /// **'Tool Result'**
  String get toolResult;

  /// No description provided for @toolResultWithDuration.
  ///
  /// In en, this message translates to:
  /// **'Tool Result ({duration}s)'**
  String toolResultWithDuration(Object duration);

  /// No description provided for @toolExecuted.
  ///
  /// In en, this message translates to:
  /// **'Executed: {name}'**
  String toolExecuted(Object name);

  /// No description provided for @toolCalling.
  ///
  /// In en, this message translates to:
  /// **'Calling: {name}...'**
  String toolCalling(Object name);

  /// No description provided for @checkStorage.
  ///
  /// In en, this message translates to:
  /// **'Check Storage'**
  String get checkStorage;

  /// No description provided for @searchDocuments.
  ///
  /// In en, this message translates to:
  /// **'Search Documents'**
  String get searchDocuments;

  /// No description provided for @optimizeNas.
  ///
  /// In en, this message translates to:
  /// **'Optimize NAS'**
  String get optimizeNas;

  /// No description provided for @attachFiles.
  ///
  /// In en, this message translates to:
  /// **'Attach files'**
  String get attachFiles;

  /// No description provided for @askAiHint.
  ///
  /// In en, this message translates to:
  /// **'Ask the AI assistant...'**
  String get askAiHint;

  /// No description provided for @checkStoragePrompt.
  ///
  /// In en, this message translates to:
  /// **'How much storage is left?'**
  String get checkStoragePrompt;

  /// No description provided for @searchDocumentsPrompt.
  ///
  /// In en, this message translates to:
  /// **'Find all PDF files in /Home'**
  String get searchDocumentsPrompt;

  /// No description provided for @optimizeNasPrompt.
  ///
  /// In en, this message translates to:
  /// **'Run a performance check'**
  String get optimizeNasPrompt;

  /// No description provided for @retryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryAction;

  /// No description provided for @editAndResend.
  ///
  /// In en, this message translates to:
  /// **'Edit and resend'**
  String get editAndResend;

  /// No description provided for @copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// No description provided for @communicationFailed.
  ///
  /// In en, this message translates to:
  /// **'Communication with AI Assistant failed.'**
  String get communicationFailed;

  /// No description provided for @clearHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistoryTitle;

  /// No description provided for @clearHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear the entire chat history?'**
  String get clearHistoryConfirm;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @responseLabel.
  ///
  /// In en, this message translates to:
  /// **'Response'**
  String get responseLabel;

  /// No description provided for @markdownLabel.
  ///
  /// In en, this message translates to:
  /// **' (Markdown)'**
  String get markdownLabel;

  /// No description provided for @aiWelcomeMessage.
  ///
  /// In en, this message translates to:
  /// **'Hello! I\'m your AI Assistant. How can I help you manage your NAS today?'**
  String get aiWelcomeMessage;

  /// Label for the rename action in the file browser
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameAction;

  /// Label for the move action in the file browser
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get moveAction;

  /// Label for the action to attach files to the AI assistant
  ///
  /// In en, this message translates to:
  /// **'Attach to AI'**
  String get attachToAiAction;

  /// Label for the delete action in the file browser
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// Label for the download action in the file browser
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadAction;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginTitle;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginButton;

  /// No description provided for @guestUser.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guestUser;

  /// No description provided for @userInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'User Info'**
  String get userInfoTitle;

  /// No description provided for @vipLabel.
  ///
  /// In en, this message translates to:
  /// **'VIP Status'**
  String get vipLabel;

  /// No description provided for @loginStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Login Status'**
  String get loginStatusLabel;

  /// No description provided for @loggedIn.
  ///
  /// In en, this message translates to:
  /// **'Logged in'**
  String get loggedIn;

  /// No description provided for @loggedOut.
  ///
  /// In en, this message translates to:
  /// **'Logged out'**
  String get loggedOut;

  /// No description provided for @aiScanTooltip.
  ///
  /// In en, this message translates to:
  /// **'AI Scan'**
  String get aiScanTooltip;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @logoutSuccess.
  ///
  /// In en, this message translates to:
  /// **'Logged out successfully.'**
  String get logoutSuccess;

  /// No description provided for @switchViewList.
  ///
  /// In en, this message translates to:
  /// **'Switch to List View'**
  String get switchViewList;

  /// No description provided for @switchViewGrid.
  ///
  /// In en, this message translates to:
  /// **'Switch to Grid View'**
  String get switchViewGrid;

  /// No description provided for @uploadFolder.
  ///
  /// In en, this message translates to:
  /// **'Upload Folder'**
  String get uploadFolder;

  /// No description provided for @transferList.
  ///
  /// In en, this message translates to:
  /// **'Transfer List'**
  String get transferList;

  /// No description provided for @transferCompleted.
  ///
  /// In en, this message translates to:
  /// **'Transfer Completed'**
  String get transferCompleted;

  /// No description provided for @transferFailed.
  ///
  /// In en, this message translates to:
  /// **'Transfer Failed'**
  String get transferFailed;

  /// No description provided for @transferInProgress.
  ///
  /// In en, this message translates to:
  /// **'Transfer In Progress'**
  String get transferInProgress;

  /// No description provided for @transferPaused.
  ///
  /// In en, this message translates to:
  /// **'Transfer Paused'**
  String get transferPaused;

  /// No description provided for @transferPending.
  ///
  /// In en, this message translates to:
  /// **'Transfer Pending'**
  String get transferPending;

  /// No description provided for @transferCancelled.
  ///
  /// In en, this message translates to:
  /// **'Transfer Cancelled'**
  String get transferCancelled;

  /// No description provided for @transferRetry.
  ///
  /// In en, this message translates to:
  /// **'Transfer Retry'**
  String get transferRetry;

  /// No description provided for @transferResume.
  ///
  /// In en, this message translates to:
  /// **'Transfer Resume'**
  String get transferResume;

  /// No description provided for @transferPause.
  ///
  /// In en, this message translates to:
  /// **'Transfer Pause'**
  String get transferPause;

  /// No description provided for @transferCancel.
  ///
  /// In en, this message translates to:
  /// **'Transfer Cancel'**
  String get transferCancel;

  /// No description provided for @transferClear.
  ///
  /// In en, this message translates to:
  /// **'Transfer Clear'**
  String get transferClear;

  /// No description provided for @transferDetails.
  ///
  /// In en, this message translates to:
  /// **'Transfer Details'**
  String get transferDetails;

  /// No description provided for @transferSpeed.
  ///
  /// In en, this message translates to:
  /// **'Transfer Speed'**
  String get transferSpeed;

  /// No description provided for @transferProgress.
  ///
  /// In en, this message translates to:
  /// **'Transfer Progress'**
  String get transferProgress;

  /// No description provided for @transferTimeRemaining.
  ///
  /// In en, this message translates to:
  /// **'Time Remaining'**
  String get transferTimeRemaining;

  /// No description provided for @transferTotalSize.
  ///
  /// In en, this message translates to:
  /// **'Total Size'**
  String get transferTotalSize;

  /// No description provided for @transferUploadedSize.
  ///
  /// In en, this message translates to:
  /// **'Uploaded Size'**
  String get transferUploadedSize;

  /// No description provided for @transferDownloadedSize.
  ///
  /// In en, this message translates to:
  /// **'Downloaded Size'**
  String get transferDownloadedSize;

  /// No description provided for @transferUploadSpeed.
  ///
  /// In en, this message translates to:
  /// **'Upload Speed'**
  String get transferUploadSpeed;

  /// No description provided for @transferDownloadSpeed.
  ///
  /// In en, this message translates to:
  /// **'Download Speed'**
  String get transferDownloadSpeed;

  /// No description provided for @transferStatus.
  ///
  /// In en, this message translates to:
  /// **'Transfer Status'**
  String get transferStatus;

  /// No description provided for @filterTooltip.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterTooltip;

  /// No description provided for @filterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter files'**
  String get filterTitle;

  /// No description provided for @filterTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get filterTypeLabel;

  /// No description provided for @filterTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma separated)'**
  String get filterTagsLabel;

  /// No description provided for @filterTagsHint.
  ///
  /// In en, this message translates to:
  /// **'tag1, tag2'**
  String get filterTagsHint;

  /// No description provided for @applyButton.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyButton;

  /// No description provided for @filterTypeImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get filterTypeImages;

  /// No description provided for @filterTypePdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get filterTypePdf;

  /// No description provided for @filterTypeDocx.
  ///
  /// In en, this message translates to:
  /// **'DOCX'**
  String get filterTypeDocx;

  /// No description provided for @filterTypeOthers.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get filterTypeOthers;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
