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
  String get createMenu => 'Create';

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
  String get deleteConfirmTitle => 'Confirm Delete';

  @override
  String get deleteBatchConfirmTitle => 'Confirm Batch Delete';

  @override
  String deleteConfirmMessage(Object name) {
    return 'Are you sure you want to delete $name?';
  }

  @override
  String deleteBatchConfirmMessage(Object count) {
    return 'Are you sure you want to delete $count items?';
  }

  @override
  String get deleteButton => 'Delete';

  @override
  String get moveTitle => 'Move Item';

  @override
  String moveBatchTitle(Object count) {
    return 'Move $count items';
  }

  @override
  String get moveTargetHint => 'Enter target path';

  @override
  String get moveButton => 'Move';

  @override
  String get renameTitle => 'Rename';

  @override
  String get folderDownloadNotSupported =>
      'Folder download is not supported yet';

  @override
  String downloadFailedMessage(Object name) {
    return 'Could not launch download for $name';
  }

  @override
  String get connectionFailedTitle => 'Connection Failed';

  @override
  String get connectionFailedMessage =>
      'Unable to communicate with the NAS server. Please ensure the server is running and your network settings are correct.';

  @override
  String get retryConnection => 'Retry Connection';

  @override
  String get sortTooltip => 'Sort';

  @override
  String get folderEmpty => 'This folder is empty';

  @override
  String get moveHere => 'Move here';

  @override
  String get copyTitle => 'Copy Item';

  @override
  String get copyHere => 'Copy here';

  @override
  String viewOriginalImage(Object size) {
    return 'View original image ($size)';
  }

  @override
  String get downloadAction => 'Download';

  @override
  String get copyAction => 'Copy';

  @override
  String get loginTitle => 'Login';

  @override
  String get usernameLabel => 'Username';

  @override
  String get passwordLabel => 'Password';

  @override
  String get loginButton => 'Login';

  @override
  String get registerTitle => 'Register';

  @override
  String get registerButton => 'Register';

  @override
  String get confirmPasswordLabel => 'Confirm Password';

  @override
  String get switchToRegisterHint => 'Don\'t have an account? Register';

  @override
  String get switchToLoginHint => 'Already have an account? Login';

  @override
  String get registrationSuccess => 'Registration successful. Please login.';

  @override
  String get loginFailed => 'Login failed. Check your username and password.';

  @override
  String get usernamePasswordRequired =>
      'Please enter both username and password.';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match.';

  @override
  String get passwordTooShort => 'Password must be at least 4 characters.';

  @override
  String get roleLabel => 'Role';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleUser => 'User';

  @override
  String get adminRegisterOffline =>
      'Admin can register even when the server is offline.';

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
  String get filterTagsEmpty => 'No tags available';

  @override
  String get applyButton => 'Apply';

  @override
  String get filterTypeImages => 'Images';

  @override
  String get filterTypePdf => 'PDF';

  @override
  String get filterTypeDocx => 'DOCX';

  @override
  String get filterTypeVideos => 'Videos';

  @override
  String get filterTypeOthers => 'Others';

  @override
  String get hostLabel => 'Server IP / Host';

  @override
  String get portLabel => 'Port';

  @override
  String get hostEmptyError => 'Host cannot be empty';

  @override
  String get portEmptyError => 'Port cannot be empty';

  @override
  String get portInvalidError => 'Invalid port (1-65535)';

  @override
  String get fontSize => 'Font Size';

  @override
  String get fontSizeSmall => 'Small';

  @override
  String get fontSizeNormal => 'Normal';

  @override
  String get fontSizeLarge => 'Large';

  @override
  String get fontSizeExtraLarge => 'Extra Large';

  @override
  String get saving => 'Saving...';

  @override
  String get settingsSaved => 'Settings saved successfully!';

  @override
  String connectionFailedLocalSaved(Object url) {
    return 'Connection failed: Unable to reach $url. Local settings saved.';
  }

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => 'Chinese';

  @override
  String get aiScanLoginRequired => 'Please login to use AI scanning.';

  @override
  String get selectAll => 'Select All';

  @override
  String get taggedLabel => 'TAGGED';

  @override
  String get aiStatusReady => 'AI Ready';

  @override
  String get aiStatusInitializing => 'AI Initializing';

  @override
  String get aiStatusDisabled => 'AI Disabled';

  @override
  String get aiStatusEnabled => 'AI Enabled';

  @override
  String get aiStatusTooltipReady =>
      'The AI system is fully operational and ready to process your files.';

  @override
  String get aiStatusTooltipInitializing =>
      'The AI engine is currently loading neural models. This usually takes 30-60 seconds depending on server hardware.';

  @override
  String get aiStatusTooltipDisabled =>
      'AI features are currently turned off in the backend configuration or the necessary models are missing.';

  @override
  String get aiStatusTooltipEnabled =>
      'The AI system is active but its full capabilities are still being verified.';

  @override
  String get aiStatusError => 'AI Error';

  @override
  String get aiEnableTitle => 'Enable AI';

  @override
  String get aiEnableHint => 'Start the AI engine and load models';

  @override
  String get aiDisableTitle => 'Disable AI';

  @override
  String get aiDisableHint => 'Stop the AI engine and free resources';

  @override
  String get aiEnablingProgress => 'Starting AI Engine...';

  @override
  String get aiDisablingProgress => 'Stopping AI Engine...';

  @override
  String get modelsAvailable => 'Models available';

  @override
  String get backendUnreachable => 'Backend server unreachable';

  @override
  String get backendUnreachableHint =>
      'Make sure the C++ backend is running to configure AI.';

  @override
  String get connected => 'Connected';

  @override
  String get offline => 'Offline';

  @override
  String get offlineBannerMessage => 'Offline: Unable to connect to NAS server';

  @override
  String get retry => 'RETRY';

  @override
  String get readAloud => 'Read aloud';

  @override
  String get stopSpeaking => 'Stop speaking';

  @override
  String get settingsSubtitle => 'Server, theme, language';

  @override
  String get aiTileTitle => 'AI';

  @override
  String get aiTileSubtitle => 'Models, RAG, HuggingFace';

  @override
  String get aiConfigTitle => 'AI Configuration';

  @override
  String setModelTitle(Object model) {
    return 'Set $model';
  }

  @override
  String get modelPathHint => 'Model path / repo ID';

  @override
  String get saveButton => 'Save';

  @override
  String modelUpdated(Object model) {
    return '$model updated';
  }

  @override
  String failedMessage(Object error) {
    return 'Failed: $error';
  }

  @override
  String checkingModel(Object model) {
    return 'Checking $model...';
  }

  @override
  String get modelExists => 'Model exists on disk';

  @override
  String get modelNotFound => 'Model not found locally';

  @override
  String checkFailed(Object error) {
    return 'Check failed: $error';
  }

  @override
  String downloadingModel(Object model) {
    return 'Downloading $model...';
  }

  @override
  String downloadSuccess(Object model) {
    return '$model downloaded successfully';
  }

  @override
  String downloadFailed(Object error) {
    return 'Download failed: $error';
  }

  @override
  String get localModels => 'Local Models';

  @override
  String get noLocalModels => 'No local models found.';

  @override
  String errorLabel(Object error) {
    return 'Error: $error';
  }

  @override
  String get activeAiModels => 'AI Features';

  @override
  String get ragSearchEngine => 'RAG & Search Engine';

  @override
  String get modelChat => 'Chat';

  @override
  String get modelVision => 'Vision';

  @override
  String get modelEmbedding => 'Embedding';

  @override
  String get loadingLabel => 'Loading...';

  @override
  String get setAction => 'Set';

  @override
  String get checkAction => 'Check';

  @override
  String elasticsearchStatus(Object status) {
    return 'Elasticsearch: $status';
  }

  @override
  String get unknownLabel => 'Unknown';

  @override
  String get naLabel => 'N/A';

  @override
  String get addressLabel => 'Address';

  @override
  String get indexLabel => 'Index';

  @override
  String get usageLabel => 'Usage';

  @override
  String indexedDocuments(int count) {
    return '$count indexed documents';
  }

  @override
  String get aiEngineLoading => 'AI Engine initializing';

  @override
  String get aiEngineError => 'AI Engine failed to initialize';

  @override
  String get modelDetailTitle => 'Model Details';

  @override
  String get modelNameLabel => 'Name';

  @override
  String get modelProviderLabel => 'Provider';

  @override
  String get modelTypeLabel => 'Type';

  @override
  String get modelPathLabel => 'Path';

  @override
  String get modelStatusLabel => 'Status';

  @override
  String get activeLabel => 'Active';

  @override
  String get inactiveLabel => 'Inactive';

  @override
  String get createdLabel => 'Created';

  @override
  String get updatedLabel => 'Updated';

  @override
  String get modelIsReadyLabel => 'Ready';

  @override
  String get isLocalLabel => 'Local';

  @override
  String get readyLabel => 'Ready';

  @override
  String get notReadyLabel => 'Not ready';

  @override
  String get downloadStartLabel => 'Download start';

  @override
  String get downloadedAtLabel => 'Downloaded at';

  @override
  String get featureDetailTitle => 'Feature Detail';

  @override
  String get changeModelLabel => 'Change Model';

  @override
  String get notSetLabel => 'Not set';

  @override
  String get indexedDocumentsTitle => 'Indexed Documents';

  @override
  String get documentNameLabel => 'Document';

  @override
  String get documentPathLabel => 'Path';

  @override
  String get noDocumentsLabel => 'No indexed documents';

  @override
  String get modelConfigLabel => 'Super Parameters';

  @override
  String get clearAllButton => 'Clear All';

  @override
  String get ragDeleteDocTitle => 'Delete Document';

  @override
  String ragDeleteDocConfirm(Object filename) {
    return 'Remove \"$filename\" from the index?';
  }

  @override
  String ragDeleteDocSuccess(Object filename) {
    return '\"$filename\" deleted from index.';
  }

  @override
  String ragDeleteDocFailed(Object error) {
    return 'Failed to delete document: $error';
  }

  @override
  String get ragClearIndexTitle => 'Clear RAG Index';

  @override
  String get ragClearIndexConfirm =>
      'Are you sure you want to delete all indexed documents? This action cannot be undone.';

  @override
  String get ragClearIndexSuccess => 'RAG index cleared successfully.';

  @override
  String ragClearIndexFailed(Object error) {
    return 'Failed to clear RAG index: $error';
  }

  @override
  String get ragClearIndexTooltip => 'Clear all indexed documents';

  @override
  String get downloadModelTitle => 'Download Model';

  @override
  String get repoIdLabel => 'Repository ID';

  @override
  String get repoIdHint => 'e.g. Qwen/Qwen2.5-7B-Instruct-GGUF';

  @override
  String get fileNameLabel => 'File Name';

  @override
  String get fileNameHint => 'e.g. qwen2.5-7b-instruct-q4_k_m.gguf';

  @override
  String get providerLabel => 'Provider';

  @override
  String downloadQueued(Object name) {
    return 'Download queued: $name';
  }

  @override
  String get modelDownloadingStatus => 'Downloading...';

  @override
  String get deleteModelLabel => 'Delete Model';

  @override
  String get reDownloadLabel => 'Re-download';

  @override
  String deleteModelConfirm(Object name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get modelDeleted => 'Model deleted';

  @override
  String modelFilesLabel(int count) {
    return 'Files ($count)';
  }

  @override
  String get modelTotalSizeLabel => 'Total Size';

  @override
  String get splitToImages => 'Split to Images';

  @override
  String get outputDirLabel => 'Output directory';

  @override
  String get outputDirHint => 'Relative to the NAS data root';

  @override
  String get selectFolder => 'Browse';

  @override
  String get startButton => 'Start';

  @override
  String get convertingPdf => 'Converting PDF pages to images...';

  @override
  String pagesConverted(int count) {
    return '$count page(s) converted.';
  }

  @override
  String get generatedFilesTitle => 'Generated files:';

  @override
  String andMore(int count) {
    return '... and $count more';
  }

  @override
  String get okButton => 'OK';

  @override
  String get selectFolderTitle => 'Select Folder';

  @override
  String get openFolder => 'Open Folder';

  @override
  String get settingServiceTitle => 'Setting & Service';

  @override
  String get mdnsPageTitle => 'mDNS Services';

  @override
  String get mdnsWebUnsupported => 'mDNS is not supported on web.';

  @override
  String get mdnsNoServicesFound => 'No mDNS services found';

  @override
  String get mdnsScanAgain => 'Scan Again';

  @override
  String get mdnsScanningServers => 'Scanning for servers...';

  @override
  String mdnsScanningForType(Object type) {
    return 'Scanning for $type...';
  }

  @override
  String get mdnsAvailableServers => 'Available AI NAS Servers';

  @override
  String get mdnsBrowseAll => 'Browse all mDNS services';

  @override
  String get mdnsNoServers => 'No servers found on local network';

  @override
  String get mdnsWebLimitationTitle => 'Web Browser Limitation';

  @override
  String get mdnsWebLimitationDesc =>
      'mDNS Service Discovery is not supported in web browsers due to security restrictions. Please ensure your NAS address is correctly configured in the app settings.';

  @override
  String get mdnsNameLabel => 'Name';

  @override
  String get mdnsHostnameLabel => 'Hostname';

  @override
  String get mdnsPriorityLabel => 'Priority';

  @override
  String get mdnsWeightLabel => 'Weight';

  @override
  String get mdnsIpv4Label => 'IPv4';

  @override
  String get mdnsIpv6Label => 'IPv6';

  @override
  String get mdnsAdditionalIpv4 => 'Additional IPv4 Addresses';

  @override
  String get mdnsAdditionalIpv6 => 'Additional IPv6 Addresses';

  @override
  String get mdnsTxtRecords => 'Properties';

  @override
  String get mdnsSetAsTarget => 'Set as Target';

  @override
  String get mdnsSetAsTargetButton => 'Set as Target AI NAS';

  @override
  String get mdnsServiceTypeLabel => 'Service Type';

  @override
  String get mdnsFilterAllTypes => 'All';

  @override
  String mdnsTargetSet(Object url) {
    return 'Target AI NAS set to $url';
  }

  @override
  String get mdnsScanTimedOut => 'Scan timed out';

  @override
  String get mdnsPageScanning => 'Scanning for mDNS services...';

  @override
  String get mdnsAddServiceTitle => 'Add Local Service';

  @override
  String get mdnsNameHint => 'My Service';

  @override
  String get mdnsHostIpLabel => 'Host / IP';

  @override
  String get mdnsHostIpHint => '0.0.0.0';

  @override
  String get mdnsPortLabel => 'Port';

  @override
  String get mdnsInvalidPort => 'Invalid port';

  @override
  String get mdnsServiceTypeHint => '_http._tcp.local.';

  @override
  String get mdnsAddButton => 'Add';

  @override
  String get mdnsAddServiceRequired => 'Required';

  @override
  String get mergeToPdf => 'Merge to PDF';

  @override
  String get mergeToPdfDialogTitle => 'Merge to PDF';

  @override
  String mergeToPdfCount(Object count) {
    return 'Merging $count files';
  }

  @override
  String get mergeToPdfFilename => 'Output filename';

  @override
  String get mergePdfsOrderHint => 'Drag or use arrows to reorder files';

  @override
  String get mergeToPdfAction => 'Merge';

  @override
  String mergeToPdfSuccess(Object filename) {
    return 'PDF created: $filename';
  }

  @override
  String get mergeToPdfFailed => 'Failed to merge files';

  @override
  String get imageType => 'Image';

  @override
  String get pdfType => 'PDF';

  @override
  String get storageTitle => 'Storage';

  @override
  String get storageRootPath => 'Storage Root Path';

  @override
  String get storageUpdateSuccess => 'Storage root updated successfully';

  @override
  String get backendProcess => 'Backend Process';

  @override
  String get pidLabel => 'PID';

  @override
  String get enterBinaryPath => 'Enter binary path';

  @override
  String get processRunning => 'Running';

  @override
  String get processStopped => 'Stopped';

  @override
  String get noProcessFound => 'No backend process found';

  @override
  String processStopConfirm(Object pid) {
    return 'Are you sure you want to stop process PID $pid?';
  }

  @override
  String get storageSubtitle => 'Disk usage, root path, process';

  @override
  String get stop => 'Stop';

  @override
  String get start => 'Start';

  @override
  String get browse => 'Browse';

  @override
  String get pathCannotBeEmpty => 'Path cannot be empty';

  @override
  String get enterBinaryPathFirst => 'Enter binary path first';

  @override
  String startBackendConfirm(Object path) {
    return 'Start backend: $path?';
  }

  @override
  String failedToStopPid(Object pid) {
    return 'Failed to stop PID $pid';
  }

  @override
  String get failedToStartBackend => 'Failed to start backend';

  @override
  String get startupOptions => 'Startup Options';

  @override
  String get runAsDaemon => 'Run as daemon (background)';

  @override
  String get notConfigured => 'Not configured';

  @override
  String get unavailable => 'Unavailable';

  @override
  String get loadingStorageUsage => 'Loading storage usage...';

  @override
  String get nasStorageStatus => 'NAS Storage Status';

  @override
  String percentUsed(Object percent) {
    return '$percent% Used';
  }

  @override
  String freeOfTotal(Object free, Object total) {
    return '$free GB Free of $total GB';
  }

  @override
  String get storageAlmostFull => 'Warning: Storage almost full!';

  @override
  String get homePageTitle => 'AI-NAS Home';

  @override
  String get listenAddressLabel => 'Listen Address';

  @override
  String get logLevelLabel => 'Log Level';

  @override
  String get logFileLabel => 'Log File';

  @override
  String get noFeaturesRegistered => 'No features registered.';

  @override
  String get versionTitle => 'Version';

  @override
  String get versionSubtitle => 'App version and logs';

  @override
  String get logViewerTitle => 'Frontend Log';

  @override
  String get logViewerSubtitle => 'View and share app logs';

  @override
  String get backendLogViewerTitle => 'Backend Log';

  @override
  String get backendLogViewerSubtitle => 'View backend server logs';

  @override
  String get logClearAction => 'Clear log';

  @override
  String get logClearConfirm => 'Are you sure you want to clear the log file?';

  @override
  String get logTruncated =>
      'Log file truncated to the last 500 KB for performance.';

  @override
  String get logFileNotFound =>
      'Log file not found. Please start using the app first.';

  @override
  String get logWebUnavailable =>
      'Log file is not available on web. Logs are printed to the browser console instead.';

  @override
  String logReadFailed(Object error) {
    return 'Failed to read log file: $error';
  }

  @override
  String get logSearchHint => 'Search log...';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get zoomIn => 'Zoom in';

  @override
  String get uploadEmpty => 'No upload tasks';

  @override
  String get showWindow => 'Show Window';

  @override
  String get quitApp => 'Quit';

  @override
  String get quitBackendRunning =>
      'Backend process is still running. Stop it before quitting?';

  @override
  String uploadTitle(int completed, int total) {
    return 'Uploads ($completed/$total)';
  }

  @override
  String uploadToPath(Object path) {
    return 'To: /$path';
  }

  @override
  String get uploadStatusUploading => 'Uploading';

  @override
  String get syncTitle => 'File Sync';

  @override
  String get syncNewConfig => 'New Sync Config';

  @override
  String get syncEmpty => 'No sync configurations';

  @override
  String get syncEmptyHint =>
      'Create a sync to copy files from your device to the NAS';

  @override
  String get syncLoadFailed => 'Failed to load sync configs';

  @override
  String get syncDeleteTitle => 'Delete Sync Config';

  @override
  String syncDeleteConfirm(Object name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String syncTriggered(int count) {
    return 'Sync completed — $count file(s) copied';
  }

  @override
  String get syncNameLabel => 'Name';

  @override
  String get syncNameHint => 'e.g. Photos Backup';

  @override
  String get syncNameRequired => 'Name is required';

  @override
  String get syncSourceLabel => 'Source (local folder)';

  @override
  String get syncSourceHint => 'Path to local folder on this device';

  @override
  String get syncSourceRequired => 'Source path is required';

  @override
  String get syncTargetLabel => 'Target (NAS folder)';

  @override
  String get syncTargetHint => 'Path on the NAS (e.g. /Backups)';

  @override
  String get syncTargetRequired => 'Target path is required';

  @override
  String get syncIntervalLabel => 'Sync interval (seconds, 0 = manual only)';

  @override
  String get syncIntervalHint => '0 for manual sync';

  @override
  String get syncPolicyLabel => 'Sync Policy';

  @override
  String get syncTypeInterval => 'Time Interval (seconds)';

  @override
  String get syncTypeDaily => 'Daily at specific time';

  @override
  String get syncTypeWatch => 'Watch folder changes';

  @override
  String get syncDailyTimeLabel => 'Sync time';

  @override
  String get syncWatchNote =>
      'Syncs automatically when files change in the source folder';

  @override
  String syncToggleFailed(Object error) {
    return 'Failed to toggle sync config: $error';
  }

  @override
  String syncTriggerFailed(Object error) {
    return 'Sync failed: $error';
  }

  @override
  String get syncDeleteFailed => 'Failed to delete sync config';

  @override
  String syncCreateFailed(Object error) {
    return 'Failed to create sync config: $error';
  }

  @override
  String get syncGetFailed => 'Failed to get sync config';

  @override
  String syncUpdateFailed(Object error) {
    return 'Failed to update sync config: $error';
  }

  @override
  String get syncTriggerNow => 'Sync now';

  @override
  String syncLastSynced(Object datetime) {
    return 'Last synced: $datetime';
  }

  @override
  String get syncBrowseLocalFolder => 'Browse local folder';

  @override
  String get syncBrowseNasFolder => 'Browse NAS folder';

  @override
  String get syncSelectTargetFolder => 'Select target folder';

  @override
  String get windowSettingsTitle => 'Window Settings';

  @override
  String get windowSettingsRegular => 'Regular';

  @override
  String get windowSettingsDialog => 'Dialog';

  @override
  String get windowSettingsTooltip => 'Tooltip';

  @override
  String get windowSettingsInitialWidth => 'Initial width';

  @override
  String get windowSettingsInitialHeight => 'Initial height';

  @override
  String get windowSettingsDecorations => 'Decorations';

  @override
  String get windowSettingsParentAnchor => 'Parent Anchor';

  @override
  String get windowSettingsChildAnchor => 'Child Anchor';

  @override
  String get windowSettingsOffset => 'Offset';

  @override
  String get windowSettingsX => 'X';

  @override
  String get windowSettingsY => 'Y';

  @override
  String get windowSettingsConstraintAdjustment => 'Constraint Adjustment';

  @override
  String get windowSettingsFlip => 'Flip';

  @override
  String get windowSettingsSlide => 'Slide';

  @override
  String get windowSettingsResize => 'Resize';

  @override
  String get editButton => 'Edit';

  @override
  String get syncEditConfig => 'Edit Sync Config';

  @override
  String get syncConfigInfo => 'Config Info';

  @override
  String get syncFileList => 'Files';

  @override
  String get syncFileListEmpty => 'No files synced yet';

  @override
  String get enabledLabel => 'Enabled';

  @override
  String get yesLabel => 'Yes';

  @override
  String get noLabel => 'No';

  @override
  String get syncLastSyncedTime => 'Last Synced';

  @override
  String get syncDeleteAfterSyncLabel => 'Delete files after sync';

  @override
  String get syncDeleteAfterSyncHint =>
      'Remove source files once they are synced to the target';

  @override
  String get syncStats => 'Stats';

  @override
  String get syncSourceCount => 'Source';

  @override
  String get syncTargetCount => 'Target';

  @override
  String get syncSyncedCount => 'Synced';

  @override
  String get syncSourceNotFound => 'Source folder not found';

  @override
  String get syncSourceEmpty => 'Source folder is empty';

  @override
  String get syncAlreadyUpToDate => 'All files are up to date';

  @override
  String get syncSourceFilesRemoved => 'Source files removed after sync';

  @override
  String get syncPendingCount => 'Pending';

  @override
  String get syncFilesFound => 'files found';

  @override
  String get syncScanning => 'Scanning...';

  @override
  String get moreOptions => 'More options';

  @override
  String get startSync => 'Sync to AINAS';

  @override
  String get pullToLocal => 'Pull to Local';

  @override
  String get syncCompleted => 'Sync completed successfully';

  @override
  String get syncFailed => 'Sync failed';

  @override
  String get syncNextSyncIn => 'Next sync in';
}
