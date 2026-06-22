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
  String viewOriginalImage(Object size) {
    return '查看原始图片 ($size)';
  }

  @override
  String get downloadAction => '下载';

  @override
  String get loginTitle => '登录';

  @override
  String get usernameLabel => '用户名';

  @override
  String get passwordLabel => '密码';

  @override
  String get loginButton => '登录';

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
  String get loggedOut => '已登出';

  @override
  String get aiScanTooltip => 'AI扫描';

  @override
  String get logout => '登出';

  @override
  String get logoutSuccess => '已成功登出。';

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
  String get connected => '已连接';

  @override
  String get offline => '离线';

  @override
  String get offlineBannerMessage => '离线：无法连接到 NAS 服务器';

  @override
  String get retry => '重试';
}
