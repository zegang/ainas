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

  @override
  String get homePage => 'Home Page';

  @override
  String get minePage => 'Mine';

  @override
  String get aiAssistant => 'AI Assistant';

  @override
  String get aiTags => 'AI Tags';

  @override
  String get aiToolName => 'AI Tool';

  @override
  String get thinkingProcess => 'Thinking Process';

  @override
  String get thinking => 'Thinking...';

  @override
  String get toolResult => 'Tool Result';

  @override
  String toolResultWithDuration(Object duration) {
    return 'Tool Result (${duration}s)';
  }

  @override
  String toolExecuted(Object name) {
    return 'Executed: $name';
  }

  @override
  String toolCalling(Object name) {
    return 'Calling: $name...';
  }

  @override
  String get checkStorage => 'Check Storage';

  @override
  String get searchDocuments => 'Search Documents';

  @override
  String get optimizeNas => 'Optimize NAS';

  @override
  String get attachFiles => 'Attach files';

  @override
  String get askAiHint => 'Ask the AI assistant...';

  @override
  String get checkStoragePrompt => 'How much storage is left?';

  @override
  String get searchDocumentsPrompt => 'Find all PDF files in /Home';

  @override
  String get optimizeNasPrompt => 'Run a performance check';

  @override
  String get retryAction => 'Retry';

  @override
  String get editAndResend => 'Edit and resend';

  @override
  String get copyText => 'Copy text';

  @override
  String get communicationFailed => 'Communication with AI Assistant failed.';

  @override
  String get clearHistoryTitle => 'Clear History';

  @override
  String get clearHistoryConfirm =>
      'Are you sure you want to clear the entire chat history?';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get responseLabel => 'Response';

  @override
  String get markdownLabel => ' (Markdown)';

  @override
  String get aiWelcomeMessage =>
      'Hello! I\'m your AI Assistant. How can I help you manage your NAS today?';

  @override
  String get renameAction => 'Rename';

  @override
  String get moveAction => 'Move';

  @override
  String get attachToAiAction => 'Attach to AI';

  @override
  String get deleteAction => 'Delete';

  @override
  String get downloadAction => 'Download';

  @override
  String get loginTitle => 'Login';

  @override
  String get usernameLabel => 'Username';

  @override
  String get passwordLabel => 'Password';

  @override
  String get loginButton => 'Login';

  @override
  String get guestUser => 'Guest';

  @override
  String get userInfoTitle => 'User Info';

  @override
  String get vipLabel => 'VIP Status';

  @override
  String get loginStatusLabel => 'Login Status';

  @override
  String get loggedIn => 'Logged in';

  @override
  String get loggedOut => 'Logged out';

  @override
  String get aiScanTooltip => 'AI Scan';

  @override
  String get logout => 'Logout';

  @override
  String get logoutSuccess => 'Logged out successfully.';

  @override
  String get switchViewList => 'Switch to List View';

  @override
  String get switchViewGrid => 'Switch to Grid View';

  @override
  String get uploadFolder => 'Upload Folder';

  @override
  String get transferList => 'Transfer List';

  @override
  String get transferCompleted => 'Transfer Completed';

  @override
  String get transferFailed => 'Transfer Failed';

  @override
  String get transferInProgress => 'Transfer In Progress';

  @override
  String get transferPaused => 'Transfer Paused';

  @override
  String get transferPending => 'Transfer Pending';

  @override
  String get transferCancelled => 'Transfer Cancelled';

  @override
  String get transferRetry => 'Transfer Retry';

  @override
  String get transferResume => 'Transfer Resume';

  @override
  String get transferPause => 'Transfer Pause';

  @override
  String get transferCancel => 'Transfer Cancel';

  @override
  String get transferClear => 'Transfer Clear';

  @override
  String get transferDetails => 'Transfer Details';

  @override
  String get transferSpeed => 'Transfer Speed';

  @override
  String get transferProgress => 'Transfer Progress';

  @override
  String get transferTimeRemaining => 'Time Remaining';

  @override
  String get transferTotalSize => 'Total Size';

  @override
  String get transferUploadedSize => 'Uploaded Size';

  @override
  String get transferDownloadedSize => 'Downloaded Size';

  @override
  String get transferUploadSpeed => 'Upload Speed';

  @override
  String get transferDownloadSpeed => 'Download Speed';

  @override
  String get transferStatus => 'Transfer Status';

  @override
  String get filterTooltip => 'Filter';

  @override
  String get filterTitle => 'Filter files';

  @override
  String get filterTypeLabel => 'Type';

  @override
  String get filterTagsLabel => 'Tags (comma separated)';

  @override
  String get filterTagsHint => 'tag1, tag2';

  @override
  String get applyButton => 'Apply';

  @override
  String get filterTypeImages => 'Images';

  @override
  String get filterTypePdf => 'PDF';

  @override
  String get filterTypeDocx => 'DOCX';

  @override
  String get filterTypeOthers => 'Others';
}
