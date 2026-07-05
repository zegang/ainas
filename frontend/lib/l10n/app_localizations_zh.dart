// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'AI-NAS';

  @override
  String get navFiles => '文件';

  @override
  String get navAiSearch => 'AI 搜索';

  @override
  String get settingsTooltip => '设置';

  @override
  String get refreshTooltip => '保存并刷新';

  @override
  String get searchHint => '搜索文件或标签';

  @override
  String get fileUploaded => '文件上传成功！';

  @override
  String get uploadLabel => '上传文件';

  @override
  String get themeMode => '主题模式';

  @override
  String get themeSystem => '系统默认';

  @override
  String get themeLight => '亮色';

  @override
  String get themeDark => '暗色';

  @override
  String get switchLanguage => '语言';

  @override
  String get testConnection => '测试连接';

  @override
  String get clear => '清除';

  @override
  String get createMenu => '新建';

  @override
  String get newFolderTitle => '新建文件夹';

  @override
  String get newFolderHint => '文件夹名称';

  @override
  String get createButton => '创建';

  @override
  String get cancelButton => '取消';

  @override
  String get selectFiles => '选择文件';

  @override
  String selectButton(Object count) {
    return '选择 ($count)';
  }

  @override
  String get homePage => '主页';

  @override
  String get minePage => '我的';

  @override
  String get aiAssistant => 'AI助手';

  @override
  String get aiTags => 'AI标签';

  @override
  String get aiToolName => 'AI工具';

  @override
  String get thinkingProcess => '思路过程';

  @override
  String get thinking => '思考中...';

  @override
  String get toolResult => '工具结果';

  @override
  String toolResultWithDuration(Object duration) {
    return '工具结果 (${duration}s)';
  }

  @override
  String toolExecuted(Object name) {
    return '已执行：$name';
  }

  @override
  String toolCalling(Object name) {
    return '调用中：$name...';
  }

  @override
  String get checkStorage => '检查存储';

  @override
  String get searchDocuments => '搜索文档';

  @override
  String get optimizeNas => '优化 NAS';

  @override
  String get attachFiles => '附加文件';

  @override
  String get askAiHint => '向AI助手提问...';

  @override
  String get checkStoragePrompt => '还有多少可用存储空间？';

  @override
  String get searchDocumentsPrompt => '查找 /Home 中所有 PDF 文件';

  @override
  String get optimizeNasPrompt => '运行性能检查';

  @override
  String get retryAction => '重试';

  @override
  String get editAndResend => '编辑并重新发送';

  @override
  String get copyText => '复制文本';

  @override
  String get communicationFailed => '与AI助手通信失败。';

  @override
  String get clearHistoryTitle => '清除历史记录';

  @override
  String get clearHistoryConfirm => '确定要清除整个聊天历史记录吗？';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get responseLabel => '响应';

  @override
  String get markdownLabel => '（Markdown）';

  @override
  String get aiWelcomeMessage => '你好！我是你的 AI 助手。我可以帮助你管理你的 NAS。今天有什么需要帮助的吗？';

  @override
  String get renameAction => '重命名';

  @override
  String get moveAction => '移动';

  @override
  String get attachToAiAction => '添加到AI';

  @override
  String get deleteAction => '删除';

  @override
  String get deleteConfirmTitle => '确认删除';

  @override
  String get deleteBatchConfirmTitle => '确认批量删除';

  @override
  String deleteConfirmMessage(Object name) {
    return '确定要删除 $name 吗？';
  }

  @override
  String deleteBatchConfirmMessage(Object count) {
    return '确定要删除 $count 个项目吗？';
  }

  @override
  String get deleteButton => '删除';

  @override
  String get moveTitle => '移动文件';

  @override
  String moveBatchTitle(Object count) {
    return '移动 $count 个项目';
  }

  @override
  String get moveTargetHint => '输入目标路径';

  @override
  String get moveButton => '移动';

  @override
  String get renameTitle => '重命名';

  @override
  String get folderDownloadNotSupported => '暂不支持下载文件夹';

  @override
  String downloadFailedMessage(Object name) {
    return '无法下载 $name';
  }

  @override
  String get connectionFailedTitle => '连接失败';

  @override
  String get connectionFailedMessage => '无法与NAS服务器通信。请确保服务器正在运行且网络设置正确。';

  @override
  String get retryConnection => '重新连接';

  @override
  String get sortTooltip => '排序';

  @override
  String get folderEmpty => '此文件夹为空';

  @override
  String get moveHere => '移动到此';

  @override
  String get copyTitle => '复制文件';

  @override
  String get copyHere => '复制到此';

  @override
  String viewOriginalImage(Object size) {
    return '查看原始图片 ($size)';
  }

  @override
  String get downloadAction => '下载';

  @override
  String get copyAction => '复制';

  @override
  String get loginTitle => '登录';

  @override
  String get usernameLabel => '用户名';

  @override
  String get passwordLabel => '密码';

  @override
  String get loginButton => '登录';

  @override
  String get registerTitle => '注册';

  @override
  String get registerButton => '注册';

  @override
  String get confirmPasswordLabel => '确认密码';

  @override
  String get switchToRegisterHint => '没有账号？注册';

  @override
  String get switchToLoginHint => '已有账号？登录';

  @override
  String get registrationSuccess => '注册成功，请登录';

  @override
  String get loginFailed => '登录失败，请检查用户名和密码';

  @override
  String get usernamePasswordRequired => '请输入用户名和密码';

  @override
  String get passwordsDoNotMatch => '两次输入的密码不一致';

  @override
  String get passwordTooShort => '密码至少需要4个字符';

  @override
  String get roleLabel => '角色';

  @override
  String get roleAdmin => '管理员';

  @override
  String get roleUser => '用户';

  @override
  String get adminRegisterOffline => '管理员可以在服务器离线时注册';

  @override
  String get guestUser => '访客';

  @override
  String get userInfoTitle => '个人信息';

  @override
  String get vipLabel => 'VIP状态';

  @override
  String get loginStatusLabel => '登录状态';

  @override
  String get loggedIn => '已登录';

  @override
  String get loggedOut => '已退出登录';

  @override
  String get aiScanTooltip => 'AI扫描';

  @override
  String get logout => '退出登录';

  @override
  String get logoutSuccess => '已成功退出登录。';

  @override
  String get switchViewList => '切换到列表视图';

  @override
  String get switchViewGrid => '切换到网格视图';

  @override
  String get uploadFolder => '上传文件夹';

  @override
  String get transferList => '传输列表';

  @override
  String get transferCompleted => '传输完成';

  @override
  String get transferFailed => '传输失败';

  @override
  String get transferInProgress => '传输中';

  @override
  String get transferPaused => '传输已暂停';

  @override
  String get transferPending => '传输待定';

  @override
  String get transferCancelled => '传输已取消';

  @override
  String get transferRetry => '传输重试';

  @override
  String get transferResume => '传输恢复';

  @override
  String get transferPause => '传输暂停';

  @override
  String get transferCancel => '传输取消';

  @override
  String get transferClear => '传输清除';

  @override
  String get transferDetails => '传输详情';

  @override
  String get transferSpeed => '传输速度';

  @override
  String get transferProgress => '传输进度';

  @override
  String get transferTimeRemaining => '剩余时间';

  @override
  String get transferTotalSize => '总大小';

  @override
  String get transferUploadedSize => '已上传大小';

  @override
  String get transferDownloadedSize => '已下载大小';

  @override
  String get transferUploadSpeed => '上传速度';

  @override
  String get transferDownloadSpeed => '下载速度';

  @override
  String get transferStatus => '传输状态';

  @override
  String get filterTooltip => '筛选';

  @override
  String get filterTitle => '筛选文件';

  @override
  String get filterTypeLabel => '类型';

  @override
  String get filterTagsLabel => '标签（以逗号分隔）';

  @override
  String get filterTagsHint => '标签1, 标签2';

  @override
  String get filterTagsEmpty => '暂无标签';

  @override
  String get applyButton => '应用';

  @override
  String get filterTypeImages => '图片';

  @override
  String get filterTypePdf => 'PDF';

  @override
  String get filterTypeDocx => 'DOCX';

  @override
  String get filterTypeVideos => '视频';

  @override
  String get filterTypeOthers => '其他';

  @override
  String get hostLabel => '服务器地址';

  @override
  String get portLabel => '端口';

  @override
  String get hostEmptyError => '主机地址不能为空';

  @override
  String get portEmptyError => '端口不能为空';

  @override
  String get portInvalidError => '端口无效（1-65535）';

  @override
  String get fontSize => '字体大小';

  @override
  String get fontSizeSmall => '小';

  @override
  String get fontSizeNormal => '标准';

  @override
  String get fontSizeLarge => '大';

  @override
  String get fontSizeExtraLarge => '特大';

  @override
  String get saving => '保存中...';

  @override
  String get settingsSaved => '设置保存成功！';

  @override
  String connectionFailedLocalSaved(Object url) {
    return '连接失败：无法访问 $url。本地设置已保存。';
  }

  @override
  String get languageEnglish => '英语';

  @override
  String get languageChinese => '中文';

  @override
  String get aiScanLoginRequired => '请登录以使用AI扫描。';

  @override
  String get selectAll => '全选';

  @override
  String get taggedLabel => '已标记';

  @override
  String get aiStatusReady => 'AI 就绪';

  @override
  String get aiStatusInitializing => 'AI 初始化中';

  @override
  String get aiStatusDisabled => 'AI 已禁用';

  @override
  String get aiStatusEnabled => 'AI 已启用';

  @override
  String get aiStatusTooltipReady => 'AI 系统已完全就绪，可以处理您的文件。';

  @override
  String get aiStatusTooltipInitializing =>
      'AI 引擎正在加载神经模型。根据服务器硬件配置，通常需要 30-60 秒。';

  @override
  String get aiStatusTooltipDisabled => 'AI 功能当前已在后端配置中关闭，或缺少必要的模型。';

  @override
  String get aiStatusTooltipEnabled => 'AI 系统已激活，但其完整功能仍在验证中。';

  @override
  String get aiStatusError => 'AI 错误';

  @override
  String get aiEnableTitle => '启用 AI';

  @override
  String get aiEnableHint => '启动 AI 引擎并加载模型';

  @override
  String get aiDisableTitle => '禁用 AI';

  @override
  String get aiDisableHint => '停止 AI 引擎并释放资源';

  @override
  String get aiEnablingProgress => '正在启动 AI 引擎...';

  @override
  String get aiDisablingProgress => '正在停止 AI 引擎...';

  @override
  String get modelsAvailable => '可用模型';

  @override
  String get backendUnreachable => '后端服务器无法访问';

  @override
  String get backendUnreachableHint => '请确保 C++ 后端正在运行以配置 AI。';

  @override
  String get connected => '已连接';

  @override
  String get offline => '离线';

  @override
  String get offlineBannerMessage => '离线：无法连接到 NAS 服务器';

  @override
  String get retry => '重试';

  @override
  String get readAloud => '朗读';

  @override
  String get stopSpeaking => '停止朗读';

  @override
  String get settingsSubtitle => '服务器、主题、语言';

  @override
  String get aiTileTitle => 'AI';

  @override
  String get aiTileSubtitle => '模型、RAG、HuggingFace';

  @override
  String get aiConfigTitle => 'AI 配置';

  @override
  String setModelTitle(Object model) {
    return '设置 $model';
  }

  @override
  String get modelPathHint => '模型路径 / 仓库 ID';

  @override
  String get saveButton => '保存';

  @override
  String modelUpdated(Object model) {
    return '$model 已更新';
  }

  @override
  String failedMessage(Object error) {
    return '失败：$error';
  }

  @override
  String checkingModel(Object model) {
    return '正在检查 $model...';
  }

  @override
  String get modelExists => '模型已存在于磁盘';

  @override
  String get modelNotFound => '本地未找到模型';

  @override
  String checkFailed(Object error) {
    return '检查失败：$error';
  }

  @override
  String downloadingModel(Object model) {
    return '正在下载 $model...';
  }

  @override
  String downloadSuccess(Object model) {
    return '$model 下载成功';
  }

  @override
  String downloadFailed(Object error) {
    return '下载失败：$error';
  }

  @override
  String get localModels => '本地模型';

  @override
  String get noLocalModels => '未找到本地模型。';

  @override
  String errorLabel(Object error) {
    return '错误：$error';
  }

  @override
  String get activeAiModels => 'AI 功能';

  @override
  String get ragSearchEngine => 'RAG 与搜索引擎';

  @override
  String get modelChat => '对话';

  @override
  String get modelVision => '视觉';

  @override
  String get modelEmbedding => '嵌入';

  @override
  String get loadingLabel => '加载中...';

  @override
  String get setAction => '设置';

  @override
  String get checkAction => '检查';

  @override
  String elasticsearchStatus(Object status) {
    return 'Elasticsearch：$status';
  }

  @override
  String get unknownLabel => '未知';

  @override
  String get naLabel => '无';

  @override
  String get addressLabel => '地址';

  @override
  String get indexLabel => '索引';

  @override
  String get usageLabel => '用量';

  @override
  String indexedDocuments(int count) {
    return '$count 个已索引文档';
  }

  @override
  String get aiEngineLoading => 'AI 引擎初始化中';

  @override
  String get aiEngineError => 'AI 引擎初始化失败';

  @override
  String get modelDetailTitle => '模型详情';

  @override
  String get modelNameLabel => '名称';

  @override
  String get modelProviderLabel => '提供商';

  @override
  String get modelTypeLabel => '类型';

  @override
  String get modelPathLabel => '路径';

  @override
  String get modelStatusLabel => '状态';

  @override
  String get activeLabel => '活跃';

  @override
  String get inactiveLabel => '非活跃';

  @override
  String get createdLabel => '创建时间';

  @override
  String get updatedLabel => '更新时间';

  @override
  String get modelIsReadyLabel => '就绪状态';

  @override
  String get isLocalLabel => '本地';

  @override
  String get readyLabel => '就绪';

  @override
  String get notReadyLabel => '未就绪';

  @override
  String get downloadStartLabel => '下载开始时间';

  @override
  String get downloadedAtLabel => '下载完成时间';

  @override
  String get featureDetailTitle => '功能详情';

  @override
  String get changeModelLabel => '更换模型';

  @override
  String get notSetLabel => '未设置';

  @override
  String get indexedDocumentsTitle => '已索引文档';

  @override
  String get documentNameLabel => '文档';

  @override
  String get documentPathLabel => '路径';

  @override
  String get noDocumentsLabel => '暂无已索引文档';

  @override
  String get modelConfigLabel => '超参数';

  @override
  String get clearAllButton => '全部清空';

  @override
  String get ragDeleteDocTitle => '删除文档';

  @override
  String ragDeleteDocConfirm(Object filename) {
    return '从索引中删除“$filename”？';
  }

  @override
  String ragDeleteDocSuccess(Object filename) {
    return '“$filename”已从索引中删除。';
  }

  @override
  String ragDeleteDocFailed(Object error) {
    return '删除文档失败：$error';
  }

  @override
  String get ragClearIndexTitle => '清空 RAG 索引';

  @override
  String get ragClearIndexConfirm => '确定要删除所有已索引的文档吗？此操作不可撤销。';

  @override
  String get ragClearIndexSuccess => 'RAG 索引已成功清空。';

  @override
  String ragClearIndexFailed(Object error) {
    return '清空 RAG 索引失败：$error';
  }

  @override
  String get ragClearIndexTooltip => '清空所有已索引文档';

  @override
  String get downloadModelTitle => '下载模型';

  @override
  String get repoIdLabel => '仓库 ID';

  @override
  String get repoIdHint => '例如 Qwen/Qwen2.5-7B-Instruct-GGUF';

  @override
  String get fileNameLabel => '文件名';

  @override
  String get fileNameHint => '例如 qwen2.5-7b-instruct-q4_k_m.gguf';

  @override
  String get providerLabel => '提供者';

  @override
  String downloadQueued(Object name) {
    return '下载已排队：$name';
  }

  @override
  String get modelDownloadingStatus => '下载中...';

  @override
  String get deleteModelLabel => '删除模型';

  @override
  String get reDownloadLabel => '重新下载';

  @override
  String deleteModelConfirm(Object name) {
    return '确认删除“$name”？';
  }

  @override
  String get modelDeleted => '模型已删除';

  @override
  String modelFilesLabel(int count) {
    return '文件 ($count)';
  }

  @override
  String get modelTotalSizeLabel => '总大小';

  @override
  String get splitToImages => '拆分 PDF 为图片';

  @override
  String get outputDirLabel => '输出目录';

  @override
  String get outputDirHint => '相对于 NAS 数据根目录';

  @override
  String get selectFolder => '浏览';

  @override
  String get startButton => '开始';

  @override
  String get convertingPdf => '正在将 PDF 页转换为图片...';

  @override
  String pagesConverted(int count) {
    return '已转换 $count 页。';
  }

  @override
  String get generatedFilesTitle => '生成的文件：';

  @override
  String andMore(int count) {
    return '... 以及其他 $count 个';
  }

  @override
  String get okButton => '确定';

  @override
  String get selectFolderTitle => '选择文件夹';

  @override
  String get openFolder => '打开文件夹';

  @override
  String get settingServiceTitle => '设置与服务';

  @override
  String get mdnsPageTitle => 'mDNS 服务';

  @override
  String get mdnsWebUnsupported => '网页端不支持 mDNS。';

  @override
  String get mdnsNoServicesFound => '未找到 mDNS 服务';

  @override
  String get mdnsScanAgain => '重新扫描';

  @override
  String get mdnsScanningServers => '正在扫描服务器...';

  @override
  String mdnsScanningForType(Object type) {
    return '正在扫描 $type...';
  }

  @override
  String get mdnsAvailableServers => '可用 AI NAS 服务器';

  @override
  String get mdnsBrowseAll => '浏览所有 mDNS 服务';

  @override
  String get mdnsNoServers => '本地网络未找到服务器';

  @override
  String get mdnsWebLimitationTitle => '浏览器限制';

  @override
  String get mdnsWebLimitationDesc =>
      '由于安全限制，网页浏览器不支持 mDNS 服务发现。请确保在应用设置中正确配置了 NAS 地址。';

  @override
  String get mdnsNameLabel => '名称';

  @override
  String get mdnsHostnameLabel => '主机名';

  @override
  String get mdnsPriorityLabel => '优先级';

  @override
  String get mdnsWeightLabel => '权重';

  @override
  String get mdnsIpv4Label => 'IPv4';

  @override
  String get mdnsIpv6Label => 'IPv6';

  @override
  String get mdnsAdditionalIpv4 => '其他 IPv4 地址';

  @override
  String get mdnsAdditionalIpv6 => '其他 IPv6 地址';

  @override
  String get mdnsTxtRecords => '属性';

  @override
  String get mdnsSetAsTarget => '设为目标';

  @override
  String get mdnsSetAsTargetButton => '设为目标 AI NAS';

  @override
  String get mdnsServiceTypeLabel => '服务类型';

  @override
  String get mdnsFilterAllTypes => '全部';

  @override
  String mdnsTargetSet(Object url) {
    return '目标 AI NAS 已设为 $url';
  }

  @override
  String get mdnsScanTimedOut => '扫描超时';

  @override
  String get mdnsPageScanning => '正在扫描 mDNS 服务...';

  @override
  String get mdnsAddServiceTitle => '添加本地服务';

  @override
  String get mdnsNameHint => '我的服务';

  @override
  String get mdnsHostIpLabel => '主机 / IP';

  @override
  String get mdnsHostIpHint => '0.0.0.0';

  @override
  String get mdnsPortLabel => '端口';

  @override
  String get mdnsInvalidPort => '无效端口';

  @override
  String get mdnsServiceTypeHint => '_http._tcp.local.';

  @override
  String get mdnsAddButton => '添加';

  @override
  String get mdnsAddServiceRequired => '必填';

  @override
  String get mergeToPdf => '合并为 PDF';

  @override
  String get mergeToPdfDialogTitle => '合并为 PDF';

  @override
  String mergeToPdfCount(Object count) {
    return '合并 $count 个文件';
  }

  @override
  String get mergeToPdfFilename => '输出文件名';

  @override
  String get mergePdfsOrderHint => '拖拽或使用箭头调整文件顺序';

  @override
  String get mergeToPdfAction => '合并';

  @override
  String mergeToPdfSuccess(Object filename) {
    return 'PDF 已创建：$filename';
  }

  @override
  String get mergeToPdfFailed => '合并文件失败';

  @override
  String get imageType => '图片';

  @override
  String get pdfType => 'PDF';

  @override
  String get storageTitle => '存储';

  @override
  String get storageRootPath => '存储根路径';

  @override
  String get storageUpdateSuccess => '存储根路径更新成功';

  @override
  String get backendProcess => '后端进程';

  @override
  String get pidLabel => '进程 ID';

  @override
  String get enterBinaryPath => '输入可执行文件路径';

  @override
  String get processRunning => '运行中';

  @override
  String get processStopped => '已停止';

  @override
  String get noProcessFound => '未找到后端进程';

  @override
  String processStopConfirm(Object pid) {
    return '确定要停止 PID $pid 的进程吗？';
  }

  @override
  String get storageSubtitle => '磁盘用量、存储路径、进程管理';

  @override
  String get stop => '停止';

  @override
  String get start => '启动';

  @override
  String get browse => '浏览';

  @override
  String get pathCannotBeEmpty => '路径不能为空';

  @override
  String get enterBinaryPathFirst => '请先输入可执行文件路径';

  @override
  String startBackendConfirm(Object path) {
    return '启动后端：$path？';
  }

  @override
  String failedToStopPid(Object pid) {
    return '停止 PID $pid 失败';
  }

  @override
  String get failedToStartBackend => '启动后端失败';

  @override
  String get startupOptions => '启动选项';

  @override
  String get runAsDaemon => '作为守护进程运行（后台）';

  @override
  String get notConfigured => '未配置';

  @override
  String get unavailable => '不可用';

  @override
  String get loadingStorageUsage => '正在加载存储用量...';

  @override
  String get nasStorageStatus => 'NAS 存储状态';

  @override
  String percentUsed(Object percent) {
    return '已用 $percent%';
  }

  @override
  String freeOfTotal(Object free, Object total) {
    return '剩余 $free GB / 总计 $total GB';
  }

  @override
  String get storageAlmostFull => '警告：存储空间即将耗尽！';

  @override
  String get homePageTitle => 'AI-NAS 首页';

  @override
  String get listenAddressLabel => '监听地址';

  @override
  String get logLevelLabel => '日志级别';

  @override
  String get logFileLabel => '日志文件';

  @override
  String get noFeaturesRegistered => '暂无可用的 AI 功能';

  @override
  String get versionTitle => '版本';

  @override
  String get versionSubtitle => '应用版本和日志';

  @override
  String get logViewerTitle => '前端日志';

  @override
  String get logViewerSubtitle => '查看和分享应用日志';

  @override
  String get backendLogViewerTitle => '后端日志';

  @override
  String get backendLogViewerSubtitle => '查看后端服务器日志';

  @override
  String get logClearAction => '清空日志';

  @override
  String get logClearConfirm => '确定要清空日志文件吗？';

  @override
  String get logTruncated => '日志文件已截断至最后 500 KB 以提升性能。';

  @override
  String get logFileNotFound => '未找到日志文件，请先使用应用。';

  @override
  String get logWebUnavailable => '日志文件在网页上不可用，日志会打印到浏览器控制台。';

  @override
  String logReadFailed(Object error) {
    return '读取日志文件失败：$error';
  }

  @override
  String get logSearchHint => '搜索日志...';

  @override
  String get zoomOut => '缩小';

  @override
  String get zoomIn => '放大';

  @override
  String get uploadEmpty => '暂无上传任务';

  @override
  String get showWindow => '显示窗口';

  @override
  String get quitApp => '退出';

  @override
  String get quitBackendRunning => '后端进程仍在运行，是否在退出前停止它？';

  @override
  String uploadTitle(int completed, int total) {
    return '上传 ($completed/$total)';
  }

  @override
  String uploadToPath(Object path) {
    return '目标：/$path';
  }

  @override
  String get uploadStatusUploading => '上传中';

  @override
  String get syncTitle => '文件同步';

  @override
  String get syncNewConfig => '新建同步';

  @override
  String get syncEmpty => '暂无同步配置';

  @override
  String get syncEmptyHint => '创建同步任务，将设备文件复制到 NAS';

  @override
  String get syncLoadFailed => '加载同步配置失败';

  @override
  String get syncDeleteTitle => '删除同步配置';

  @override
  String syncDeleteConfirm(Object name) {
    return '确定要删除同步 \"$name\" 吗？';
  }

  @override
  String syncTriggered(int count) {
    return '同步完成 — 已复制 $count 个文件';
  }

  @override
  String get syncNameLabel => '名称';

  @override
  String get syncNameHint => '例如：照片备份';

  @override
  String get syncNameRequired => '名称不能为空';

  @override
  String get syncSourceLabel => '源路径（本地文件夹）';

  @override
  String get syncSourceHint => '设备上的本地文件夹路径';

  @override
  String get syncSourceRequired => '源路径不能为空';

  @override
  String get syncTargetLabel => '目标路径（NAS 文件夹）';

  @override
  String get syncTargetHint => 'NAS 上的路径（如 /Backups）';

  @override
  String get syncTargetRequired => '目标路径不能为空';

  @override
  String get syncIntervalLabel => '同步间隔（秒，0 = 仅手动）';

  @override
  String get syncIntervalHint => '0 表示仅手动同步';

  @override
  String get syncPolicyLabel => '同步策略';

  @override
  String get syncTypeInterval => '时间间隔（秒）';

  @override
  String get syncTypeDaily => '每天指定时间同步';

  @override
  String get syncTypeWatch => '监控文件夹变化';

  @override
  String get syncDailyTimeLabel => '同步时间';

  @override
  String get syncWatchNote => '源文件夹中文件发生变化时自动同步';

  @override
  String syncToggleFailed(Object error) {
    return '切换同步配置失败：$error';
  }

  @override
  String syncTriggerFailed(Object error) {
    return '同步失败：$error';
  }

  @override
  String get syncDeleteFailed => '删除同步配置失败';

  @override
  String syncCreateFailed(Object error) {
    return '创建同步配置失败：$error';
  }

  @override
  String get syncGetFailed => '获取同步配置失败';

  @override
  String syncUpdateFailed(Object error) {
    return '更新同步配置失败：$error';
  }

  @override
  String get syncTriggerNow => '立即同步';

  @override
  String syncLastSynced(Object datetime) {
    return '上次同步：$datetime';
  }

  @override
  String get syncBrowseLocalFolder => '浏览本地文件夹';

  @override
  String get syncBrowseNasFolder => '浏览 NAS 文件夹';

  @override
  String get syncSelectTargetFolder => '选择目标文件夹';

  @override
  String get windowSettingsTitle => '窗口设置';

  @override
  String get windowSettingsRegular => '常规';

  @override
  String get windowSettingsDialog => '对话框';

  @override
  String get windowSettingsTooltip => '工具提示';

  @override
  String get windowSettingsInitialWidth => '初始宽度';

  @override
  String get windowSettingsInitialHeight => '初始高度';

  @override
  String get windowSettingsDecorations => '装饰';

  @override
  String get windowSettingsParentAnchor => '父锚点';

  @override
  String get windowSettingsChildAnchor => '子锚点';

  @override
  String get windowSettingsOffset => '偏移';

  @override
  String get windowSettingsX => 'X';

  @override
  String get windowSettingsY => 'Y';

  @override
  String get windowSettingsConstraintAdjustment => '约束调整';

  @override
  String get windowSettingsFlip => '翻转';

  @override
  String get windowSettingsSlide => '滑动';

  @override
  String get windowSettingsResize => '调整大小';

  @override
  String get editButton => '编辑';

  @override
  String get syncEditConfig => '编辑同步配置';

  @override
  String get syncConfigInfo => '配置信息';

  @override
  String get syncFileList => '文件列表';

  @override
  String get syncFileListEmpty => '暂无已同步文件';

  @override
  String get enabledLabel => '已启用';

  @override
  String get yesLabel => '是';

  @override
  String get noLabel => '否';

  @override
  String get syncLastSyncedTime => '上次同步时间';

  @override
  String get syncDeleteAfterSyncLabel => '同步后删除源文件';

  @override
  String get syncDeleteAfterSyncHint => '文件同步到目标后删除源文件';

  @override
  String get syncStats => '统计';

  @override
  String get syncSourceCount => '源文件';

  @override
  String get syncTargetCount => '目标文件';

  @override
  String get syncSyncedCount => '已同步';

  @override
  String get syncSourceNotFound => '源文件夹不存在';

  @override
  String get syncSourceEmpty => '源文件夹为空';

  @override
  String get syncAlreadyUpToDate => '所有文件已是最新';

  @override
  String get syncSourceFilesRemoved => '同步后已删除源文件';

  @override
  String get syncPendingCount => '待同步';

  @override
  String get syncFilesFound => '个文件';

  @override
  String get syncScanning => '正在扫描...';

  @override
  String get moreOptions => '更多选项';

  @override
  String get startSync => '同步到 AINAS';

  @override
  String get pullToLocal => '拉取到本地';

  @override
  String get syncCompleted => '同步完成';

  @override
  String get syncFailed => '同步失败';
}
