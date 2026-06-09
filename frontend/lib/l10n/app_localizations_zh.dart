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
  String get aiAssistant => 'AI 助手';

  @override
  String get renameAction => '重命名';

  @override
  String get moveAction => '移动';

  @override
  String get attachToAiAction => '添加到 AI';

  @override
  String get deleteAction => '删除';
}
