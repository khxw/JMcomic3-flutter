import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/android_display_mode.dart';
import 'package:jmcomic3/configs/app_font_size.dart';
import 'package:jmcomic3/configs/app_locale.dart';
import 'package:jmcomic3/configs/app_orientation.dart';
import 'package:jmcomic3/configs/categories_sort.dart';
import 'package:jmcomic3/configs/display_jmcode.dart';
import 'package:jmcomic3/configs/download_and_export_to.dart';
import 'package:jmcomic3/configs/export_rename.dart';
import 'package:jmcomic3/configs/ignore_upgrade_pop.dart';
import 'package:jmcomic3/configs/ignore_view_log.dart';
import 'package:jmcomic3/configs/is_pro.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/configs/network_api_host.dart';
import 'package:jmcomic3/configs/network_cdn_host.dart';
import 'package:jmcomic3/configs/no_animation.dart';
import 'package:jmcomic3/configs/proxy.dart';
import 'package:jmcomic3/configs/search_title_words.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/configs/two_page_direction.dart';
import 'package:jmcomic3/configs/using_right_click_pop.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/configs/volume_key_control.dart';
import 'package:jmcomic3/configs/web_dav_password.dart';
import 'package:jmcomic3/configs/web_dav_sync_switch.dart';
import 'package:jmcomic3/configs/web_dav_url.dart';
import 'package:jmcomic3/configs/web_dav_username.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/downloads_exports_screen2.dart';

import '../basic/commons.dart';
import '../basic/web_dav_sync.dart';
import '../configs/Authentication.dart';
import '../configs/disable_recommend_content.dart';
import 'components/right_click_pop.dart';
import 'init_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      key: const ValueKey('settings-page'),
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              key: const ValueKey('settings-list'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _SettingsSection(
                  sectionKey: const ValueKey('settings-common'),
                  icon: Icons.tune_rounded,
                  title: l10n.tr('常用设置', en: 'Common settings'),
                  subtitle: l10n.tr(
                    '刷新率、外观、语言与显示',
                    en: 'Refresh rate, appearance, language and display',
                  ),
                  initiallyExpanded: true,
                  children: [
                    androidDisplayModeSetting(),
                    const Divider(height: 1),
                    themeSetting(context),
                    appLocaleSetting(context),
                    const Divider(height: 1),
                    ...fontSizeAdjustSettings(),
                  ],
                ),
                _SettingsSection(
                  sectionKey: const ValueKey('settings-reading'),
                  icon: Icons.menu_book_rounded,
                  title: l10n.sectionReading,
                  subtitle: l10n.tr(
                    '阅读操作与双页方向',
                    en: 'Reading controls and spread direction',
                  ),
                  children: [
                    volumeKeyControlSetting(),
                    noAnimationSetting(),
                    const Divider(height: 1),
                    twoGalleryDirectionSetting(context),
                  ],
                ),
                _SettingsSection(
                  sectionKey: const ValueKey('settings-storage'),
                  icon: Icons.download_for_offline_rounded,
                  title: l10n.tr('下载与存储', en: 'Downloads and storage'),
                  subtitle: l10n.tr(
                    '保存位置、导出命名与未完成任务',
                    en: 'Save location, export naming and unfinished tasks',
                  ),
                  children: [
                    downloadDirectorySetting(),
                    const Divider(height: 1),
                    exportRenameSetting(),
                    const Divider(height: 1),
                    ListTile(
                      key: const ValueKey('settings-export-incomplete'),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DownloadsExportScreen2(),
                          ),
                        );
                      },
                      title: Text(l10n.exportIncomplete),
                    ),
                  ],
                ),
                _SettingsSection(
                  sectionKey: const ValueKey('settings-account'),
                  icon: Icons.manage_accounts_rounded,
                  title: l10n.sectionUserNetwork,
                  subtitle: l10n.tr(
                    '接口、网络与账号收藏夹',
                    en: 'API, network and account favorites',
                  ),
                  children: [
                    apiHostSetting(),
                    cdnHostSetting(),
                    proxySetting(),
                    const Divider(height: 1),
                    createFavoriteFolderItemTile(context),
                    deleteFavoriteFolderItemTile(context),
                    renameFavoriteFolderItemTile(context),
                    const Divider(height: 1),
                    ListTile(
                      key: const ValueKey('settings-clear-account'),
                      onTap: () async {
                        if (await confirmDialog(
                          context,
                          l10n.clearAccount,
                          l10n.clearAccountConfirm,
                        )) {
                          await methods.logout();
                          if (!mounted) return;
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (BuildContext context) =>
                                  const InitScreen(),
                            ),
                            (route) => false,
                          );
                        }
                      },
                      title: Text(l10n.clearAccount),
                    ),
                  ],
                ),
                _SettingsSection(
                  sectionKey: const ValueKey('settings-sync'),
                  icon: Icons.cloud_sync_rounded,
                  title: l10n.sectionSync,
                  subtitle: l10n.tr(
                    'WebDAV 备份与同步',
                    en: 'WebDAV backup and sync',
                  ),
                  children: [
                    webDavSyncSwitchSetting(),
                    webDavUrlSetting(),
                    webDavUserNameSetting(),
                    webDavPasswordSetting(),
                    webDavSyncClick(context),
                    webDavSyncUploadClick(context),
                    webDavSyncDownloadClick(context),
                  ],
                ),
                _SettingsSection(
                  sectionKey: const ValueKey('settings-system'),
                  icon: Icons.dashboard_customize_rounded,
                  title: l10n.tr('显示与应用', en: 'Display and app'),
                  subtitle: l10n.tr(
                    '内容显示、操作方式与高级选项',
                    en: 'Content display, interaction and advanced options',
                  ),
                  children: [
                    displayJmcodeSetting(),
                    searchTitleWordsSetting(),
                    categoriesSortSetting(context),
                    appOrientationWidget(),
                    disableRecommendContentSetting(),
                    const Divider(height: 1),
                    usingRightClickPopSetting(),
                    authenticationSetting(),
                    ignoreVewLogSetting(),
                    const Divider(height: 1),
                    userAgreementSetting(context),
                    if (!updatesTemporarilyDisabled && hasProAccess) ...[
                      const Divider(height: 1),
                      autoUpdateCheckSetting(),
                      ignoreUpgradePopSetting(),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final Key sectionKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _SettingsSection({
    required this.sectionKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: sectionKey,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .5),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          maintainState: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: scheme.primary, size: 20),
          ),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          children: children,
        ),
      ),
    );
  }
}
