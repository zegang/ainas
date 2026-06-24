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

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteBatchConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Batch Delete'**
  String get deleteBatchConfirmTitle;

  /// No description provided for @deleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {name}?'**
  String deleteConfirmMessage(Object name);

  /// No description provided for @deleteBatchConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {count} items?'**
  String deleteBatchConfirmMessage(Object count);

  /// No description provided for @deleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteButton;

  /// No description provided for @moveTitle.
  ///
  /// In en, this message translates to:
  /// **'Move Item'**
  String get moveTitle;

  /// No description provided for @moveBatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Move {count} items'**
  String moveBatchTitle(Object count);

  /// No description provided for @moveTargetHint.
  ///
  /// In en, this message translates to:
  /// **'Enter target path'**
  String get moveTargetHint;

  /// No description provided for @moveButton.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get moveButton;

  /// No description provided for @renameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameTitle;

  /// No description provided for @folderDownloadNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Folder download is not supported yet'**
  String get folderDownloadNotSupported;

  /// No description provided for @downloadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not launch download for {name}'**
  String downloadFailedMessage(Object name);

  /// No description provided for @connectionFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection Failed'**
  String get connectionFailedTitle;

  /// No description provided for @connectionFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Unable to communicate with the NAS server. Please ensure the server is running and your network settings are correct.'**
  String get connectionFailedMessage;

  /// No description provided for @retryConnection.
  ///
  /// In en, this message translates to:
  /// **'Retry Connection'**
  String get retryConnection;

  /// No description provided for @sortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortTooltip;

  /// No description provided for @folderEmpty.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get folderEmpty;

  /// No description provided for @moveHere.
  ///
  /// In en, this message translates to:
  /// **'Move here'**
  String get moveHere;

  /// No description provided for @copyTitle.
  ///
  /// In en, this message translates to:
  /// **'Copy Item'**
  String get copyTitle;

  /// No description provided for @copyHere.
  ///
  /// In en, this message translates to:
  /// **'Copy here'**
  String get copyHere;

  /// No description provided for @viewOriginalImage.
  ///
  /// In en, this message translates to:
  /// **'View original image ({size})'**
  String viewOriginalImage(Object size);

  /// Label for the download action in the file browser
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadAction;

  /// Label for the copy action in the file browser
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyAction;

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

  /// No description provided for @filterTagsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tags available'**
  String get filterTagsEmpty;

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

  /// No description provided for @hostLabel.
  ///
  /// In en, this message translates to:
  /// **'Server IP / Host'**
  String get hostLabel;

  /// No description provided for @portLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get portLabel;

  /// No description provided for @hostEmptyError.
  ///
  /// In en, this message translates to:
  /// **'Host cannot be empty'**
  String get hostEmptyError;

  /// No description provided for @portEmptyError.
  ///
  /// In en, this message translates to:
  /// **'Port cannot be empty'**
  String get portEmptyError;

  /// No description provided for @portInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Invalid port (1-65535)'**
  String get portInvalidError;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get fontSize;

  /// No description provided for @fontSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get fontSizeSmall;

  /// No description provided for @fontSizeNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get fontSizeNormal;

  /// No description provided for @fontSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get fontSizeLarge;

  /// No description provided for @fontSizeExtraLarge.
  ///
  /// In en, this message translates to:
  /// **'Extra Large'**
  String get fontSizeExtraLarge;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved successfully!'**
  String get settingsSaved;

  /// No description provided for @connectionFailedLocalSaved.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: Unable to reach {url}. Local settings saved.'**
  String connectionFailedLocalSaved(Object url);

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageChinese;

  /// No description provided for @aiScanLoginRequired.
  ///
  /// In en, this message translates to:
  /// **'Please login to use AI scanning.'**
  String get aiScanLoginRequired;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @taggedLabel.
  ///
  /// In en, this message translates to:
  /// **'TAGGED'**
  String get taggedLabel;

  /// No description provided for @aiStatusReady.
  ///
  /// In en, this message translates to:
  /// **'AI Ready'**
  String get aiStatusReady;

  /// No description provided for @aiStatusInitializing.
  ///
  /// In en, this message translates to:
  /// **'AI Initializing'**
  String get aiStatusInitializing;

  /// No description provided for @aiStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'AI Disabled'**
  String get aiStatusDisabled;

  /// No description provided for @aiStatusEnabled.
  ///
  /// In en, this message translates to:
  /// **'AI Enabled'**
  String get aiStatusEnabled;

  /// No description provided for @aiStatusTooltipReady.
  ///
  /// In en, this message translates to:
  /// **'The AI system is fully operational and ready to process your files.'**
  String get aiStatusTooltipReady;

  /// No description provided for @aiStatusTooltipInitializing.
  ///
  /// In en, this message translates to:
  /// **'The AI engine is currently loading neural models. This usually takes 30-60 seconds depending on server hardware.'**
  String get aiStatusTooltipInitializing;

  /// No description provided for @aiStatusTooltipDisabled.
  ///
  /// In en, this message translates to:
  /// **'AI features are currently turned off in the backend configuration or the necessary models are missing.'**
  String get aiStatusTooltipDisabled;

  /// No description provided for @aiStatusTooltipEnabled.
  ///
  /// In en, this message translates to:
  /// **'The AI system is active but its full capabilities are still being verified.'**
  String get aiStatusTooltipEnabled;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @offlineBannerMessage.
  ///
  /// In en, this message translates to:
  /// **'Offline: Unable to connect to NAS server'**
  String get offlineBannerMessage;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get retry;

  /// No description provided for @readAloud.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get readAloud;

  /// No description provided for @stopSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Stop speaking'**
  String get stopSpeaking;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Server, theme, language'**
  String get settingsSubtitle;

  /// No description provided for @aiTileTitle.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get aiTileTitle;

  /// No description provided for @aiTileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Models, RAG, HuggingFace'**
  String get aiTileSubtitle;

  /// No description provided for @aiConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Configuration'**
  String get aiConfigTitle;

  /// No description provided for @setModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Set {model}'**
  String setModelTitle(Object model);

  /// No description provided for @modelPathHint.
  ///
  /// In en, this message translates to:
  /// **'Model path / repo ID'**
  String get modelPathHint;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @modelUpdated.
  ///
  /// In en, this message translates to:
  /// **'{model} updated'**
  String modelUpdated(Object model);

  /// No description provided for @failedMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String failedMessage(Object error);

  /// No description provided for @checkingModel.
  ///
  /// In en, this message translates to:
  /// **'Checking {model}...'**
  String checkingModel(Object model);

  /// No description provided for @modelExists.
  ///
  /// In en, this message translates to:
  /// **'Model exists on disk'**
  String get modelExists;

  /// No description provided for @modelNotFound.
  ///
  /// In en, this message translates to:
  /// **'Model not found locally'**
  String get modelNotFound;

  /// No description provided for @checkFailed.
  ///
  /// In en, this message translates to:
  /// **'Check failed: {error}'**
  String checkFailed(Object error);

  /// No description provided for @downloadingModel.
  ///
  /// In en, this message translates to:
  /// **'Downloading {model}...'**
  String downloadingModel(Object model);

  /// No description provided for @downloadSuccess.
  ///
  /// In en, this message translates to:
  /// **'{model} downloaded successfully'**
  String downloadSuccess(Object model);

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String downloadFailed(Object error);

  /// No description provided for @localModels.
  ///
  /// In en, this message translates to:
  /// **'Local Models'**
  String get localModels;

  /// No description provided for @noLocalModels.
  ///
  /// In en, this message translates to:
  /// **'No local models found.'**
  String get noLocalModels;

  /// No description provided for @errorLabel.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorLabel(Object error);

  /// No description provided for @activeAiModels.
  ///
  /// In en, this message translates to:
  /// **'AI Features'**
  String get activeAiModels;

  /// No description provided for @ragSearchEngine.
  ///
  /// In en, this message translates to:
  /// **'RAG & Search Engine'**
  String get ragSearchEngine;

  /// No description provided for @modelChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get modelChat;

  /// No description provided for @modelVision.
  ///
  /// In en, this message translates to:
  /// **'Vision'**
  String get modelVision;

  /// No description provided for @modelEmbedding.
  ///
  /// In en, this message translates to:
  /// **'Embedding'**
  String get modelEmbedding;

  /// No description provided for @loadingLabel.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loadingLabel;

  /// No description provided for @setAction.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get setAction;

  /// No description provided for @checkAction.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get checkAction;

  /// No description provided for @elasticsearchStatus.
  ///
  /// In en, this message translates to:
  /// **'Elasticsearch: {status}'**
  String elasticsearchStatus(Object status);

  /// No description provided for @unknownLabel.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownLabel;

  /// No description provided for @naLabel.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get naLabel;

  /// No description provided for @addressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get addressLabel;

  /// No description provided for @indexLabel.
  ///
  /// In en, this message translates to:
  /// **'Index'**
  String get indexLabel;

  /// No description provided for @usageLabel.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get usageLabel;

  /// No description provided for @indexedDocuments.
  ///
  /// In en, this message translates to:
  /// **'{count} indexed documents'**
  String indexedDocuments(int count);

  /// No description provided for @aiEngineLoading.
  ///
  /// In en, this message translates to:
  /// **'AI Engine initializing'**
  String get aiEngineLoading;

  /// No description provided for @aiEngineError.
  ///
  /// In en, this message translates to:
  /// **'AI Engine failed to initialize'**
  String get aiEngineError;

  /// No description provided for @modelDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Model Details'**
  String get modelDetailTitle;

  /// No description provided for @modelNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get modelNameLabel;

  /// No description provided for @modelProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get modelProviderLabel;

  /// No description provided for @modelTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get modelTypeLabel;

  /// No description provided for @modelPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get modelPathLabel;

  /// No description provided for @modelStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get modelStatusLabel;

  /// No description provided for @activeLabel.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeLabel;

  /// No description provided for @inactiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactiveLabel;

  /// No description provided for @createdLabel.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get createdLabel;

  /// No description provided for @updatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get updatedLabel;

  /// No description provided for @modelIsReadyLabel.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get modelIsReadyLabel;

  /// No description provided for @isLocalLabel.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get isLocalLabel;

  /// No description provided for @readyLabel.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get readyLabel;

  /// No description provided for @notReadyLabel.
  ///
  /// In en, this message translates to:
  /// **'Not ready'**
  String get notReadyLabel;

  /// No description provided for @downloadStartLabel.
  ///
  /// In en, this message translates to:
  /// **'Download start'**
  String get downloadStartLabel;

  /// No description provided for @downloadedAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Downloaded at'**
  String get downloadedAtLabel;

  /// No description provided for @featureDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Feature Detail'**
  String get featureDetailTitle;

  /// No description provided for @changeModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Change Model'**
  String get changeModelLabel;

  /// No description provided for @notSetLabel.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSetLabel;

  /// No description provided for @indexedDocumentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Indexed Documents'**
  String get indexedDocumentsTitle;

  /// No description provided for @documentNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get documentNameLabel;

  /// No description provided for @documentPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get documentPathLabel;

  /// No description provided for @noDocumentsLabel.
  ///
  /// In en, this message translates to:
  /// **'No indexed documents'**
  String get noDocumentsLabel;

  /// No description provided for @modelConfigLabel.
  ///
  /// In en, this message translates to:
  /// **'Super Parameters'**
  String get modelConfigLabel;

  /// No description provided for @clearAllButton.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clearAllButton;

  /// No description provided for @ragDeleteDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Document'**
  String get ragDeleteDocTitle;

  /// No description provided for @ragDeleteDocConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{filename}\" from the index?'**
  String ragDeleteDocConfirm(Object filename);

  /// No description provided for @ragDeleteDocSuccess.
  ///
  /// In en, this message translates to:
  /// **'\"{filename}\" deleted from index.'**
  String ragDeleteDocSuccess(Object filename);

  /// No description provided for @ragDeleteDocFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete document: {error}'**
  String ragDeleteDocFailed(Object error);

  /// No description provided for @ragClearIndexTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear RAG Index'**
  String get ragClearIndexTitle;

  /// No description provided for @ragClearIndexConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all indexed documents? This action cannot be undone.'**
  String get ragClearIndexConfirm;

  /// No description provided for @ragClearIndexSuccess.
  ///
  /// In en, this message translates to:
  /// **'RAG index cleared successfully.'**
  String get ragClearIndexSuccess;

  /// No description provided for @ragClearIndexFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to clear RAG index: {error}'**
  String ragClearIndexFailed(Object error);

  /// No description provided for @ragClearIndexTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear all indexed documents'**
  String get ragClearIndexTooltip;

  /// No description provided for @downloadModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Download Model'**
  String get downloadModelTitle;

  /// No description provided for @repoIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Repository ID'**
  String get repoIdLabel;

  /// No description provided for @repoIdHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Qwen/Qwen2.5-7B-Instruct-GGUF'**
  String get repoIdHint;

  /// No description provided for @fileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'File Name'**
  String get fileNameLabel;

  /// No description provided for @fileNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. qwen2.5-7b-instruct-q4_k_m.gguf'**
  String get fileNameHint;

  /// No description provided for @providerLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get providerLabel;

  /// No description provided for @downloadQueued.
  ///
  /// In en, this message translates to:
  /// **'Download queued: {name}'**
  String downloadQueued(Object name);

  /// No description provided for @modelDownloadingStatus.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get modelDownloadingStatus;

  /// No description provided for @deleteModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete Model'**
  String get deleteModelLabel;

  /// No description provided for @reDownloadLabel.
  ///
  /// In en, this message translates to:
  /// **'Re-download'**
  String get reDownloadLabel;

  /// No description provided for @deleteModelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteModelConfirm(Object name);

  /// No description provided for @modelDeleted.
  ///
  /// In en, this message translates to:
  /// **'Model deleted'**
  String get modelDeleted;

  /// No description provided for @modelFilesLabel.
  ///
  /// In en, this message translates to:
  /// **'Files ({count})'**
  String modelFilesLabel(int count);

  /// No description provided for @modelTotalSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Size'**
  String get modelTotalSizeLabel;

  /// No description provided for @splitToImages.
  ///
  /// In en, this message translates to:
  /// **'Split to Images'**
  String get splitToImages;

  /// No description provided for @outputDirLabel.
  ///
  /// In en, this message translates to:
  /// **'Output directory'**
  String get outputDirLabel;

  /// No description provided for @outputDirHint.
  ///
  /// In en, this message translates to:
  /// **'Relative to the NAS data root'**
  String get outputDirHint;

  /// No description provided for @selectFolder.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get selectFolder;

  /// No description provided for @startButton.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get startButton;

  /// No description provided for @convertingPdf.
  ///
  /// In en, this message translates to:
  /// **'Converting PDF pages to images...'**
  String get convertingPdf;

  /// No description provided for @pagesConverted.
  ///
  /// In en, this message translates to:
  /// **'{count} page(s) converted.'**
  String pagesConverted(int count);

  /// No description provided for @generatedFilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Generated files:'**
  String get generatedFilesTitle;

  /// No description provided for @andMore.
  ///
  /// In en, this message translates to:
  /// **'... and {count} more'**
  String andMore(int count);

  /// No description provided for @okButton.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okButton;

  /// No description provided for @selectFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Folder'**
  String get selectFolderTitle;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get openFolder;

  /// No description provided for @settingServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Setting & Service'**
  String get settingServiceTitle;

  /// No description provided for @mdnsPageTitle.
  ///
  /// In en, this message translates to:
  /// **'mDNS Services'**
  String get mdnsPageTitle;

  /// No description provided for @mdnsWebUnsupported.
  ///
  /// In en, this message translates to:
  /// **'mDNS is not supported on web.'**
  String get mdnsWebUnsupported;

  /// No description provided for @mdnsNoServicesFound.
  ///
  /// In en, this message translates to:
  /// **'No mDNS services found'**
  String get mdnsNoServicesFound;

  /// No description provided for @mdnsScanAgain.
  ///
  /// In en, this message translates to:
  /// **'Scan Again'**
  String get mdnsScanAgain;

  /// No description provided for @mdnsScanningServers.
  ///
  /// In en, this message translates to:
  /// **'Scanning for servers...'**
  String get mdnsScanningServers;

  /// No description provided for @mdnsAvailableServers.
  ///
  /// In en, this message translates to:
  /// **'Available AI NAS Servers'**
  String get mdnsAvailableServers;

  /// No description provided for @mdnsBrowseAll.
  ///
  /// In en, this message translates to:
  /// **'Browse all mDNS services'**
  String get mdnsBrowseAll;

  /// No description provided for @mdnsNoServers.
  ///
  /// In en, this message translates to:
  /// **'No servers found on local network'**
  String get mdnsNoServers;

  /// No description provided for @mdnsWebLimitationTitle.
  ///
  /// In en, this message translates to:
  /// **'Web Browser Limitation'**
  String get mdnsWebLimitationTitle;

  /// No description provided for @mdnsWebLimitationDesc.
  ///
  /// In en, this message translates to:
  /// **'mDNS Service Discovery is not supported in web browsers due to security restrictions. Please ensure your NAS address is correctly configured in the app settings.'**
  String get mdnsWebLimitationDesc;

  /// No description provided for @mdnsNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get mdnsNameLabel;

  /// No description provided for @mdnsHostnameLabel.
  ///
  /// In en, this message translates to:
  /// **'Hostname'**
  String get mdnsHostnameLabel;

  /// No description provided for @mdnsPriorityLabel.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get mdnsPriorityLabel;

  /// No description provided for @mdnsWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get mdnsWeightLabel;

  /// No description provided for @mdnsIpv4Label.
  ///
  /// In en, this message translates to:
  /// **'IPv4'**
  String get mdnsIpv4Label;

  /// No description provided for @mdnsIpv6Label.
  ///
  /// In en, this message translates to:
  /// **'IPv6'**
  String get mdnsIpv6Label;

  /// No description provided for @mdnsAdditionalIpv4.
  ///
  /// In en, this message translates to:
  /// **'Additional IPv4 Addresses'**
  String get mdnsAdditionalIpv4;

  /// No description provided for @mdnsAdditionalIpv6.
  ///
  /// In en, this message translates to:
  /// **'Additional IPv6 Addresses'**
  String get mdnsAdditionalIpv6;

  /// No description provided for @mdnsTxtRecords.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get mdnsTxtRecords;

  /// No description provided for @mdnsSetAsTarget.
  ///
  /// In en, this message translates to:
  /// **'Set as Target'**
  String get mdnsSetAsTarget;

  /// No description provided for @mdnsSetAsTargetButton.
  ///
  /// In en, this message translates to:
  /// **'Set as Target AI NAS'**
  String get mdnsSetAsTargetButton;

  /// No description provided for @mdnsServiceTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Service Type'**
  String get mdnsServiceTypeLabel;

  /// No description provided for @mdnsTargetSet.
  ///
  /// In en, this message translates to:
  /// **'Target AI NAS set to {url}'**
  String mdnsTargetSet(Object url);
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
