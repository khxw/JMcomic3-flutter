import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/app_back_button.dart';
import 'package:jmcomic3/screens/components/app_icon.dart';
import 'package:jmcomic3/screens/components/badge.dart';
import 'package:jmcomic3/screens/components/right_click_pop.dart';
import 'package:jmcomic3/screens/open_source_license_screen.dart';
import 'package:jmcomic3/screens/update_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  static const _projectUrl = 'https://github.com/khxw/JMcomic3-flutter';

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: _buildScreen(context), context: context);
  }

  Widget _buildScreen(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      key: const ValueKey('about-page'),
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.l10n.about),
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AboutHeader(version: currentVersion()),
                  const SizedBox(height: 14),
                  Material(
                    color: scheme.surfaceContainerLow,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: .5),
                      ),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          key: const ValueKey('about-project-link'),
                          leading: const Icon(Icons.code_rounded),
                          title: Text(
                            context.l10n.tr('项目主页', en: 'Project homepage'),
                          ),
                          subtitle: const Text(_projectUrl),
                          trailing: const Icon(Icons.open_in_new_rounded),
                          onTap: () => openUrl(_projectUrl),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          key: const ValueKey('about-update-entry'),
                          leading: const Icon(Icons.system_update_alt_rounded),
                          title: Text(
                            context.l10n.tr('检查更新', en: 'Check for updates'),
                          ),
                          subtitle: Text(
                            context.l10n.tr(
                              '查看版本状态和更新日志',
                              en: 'View version status and release notes',
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const UpdateScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          key: const ValueKey('about-license-entry'),
                          leading: const Icon(Icons.policy_outlined),
                          title: Text(
                            context.l10n.tr(
                              '开源许可',
                              en: 'Open-source licenses',
                            ),
                          ),
                          subtitle: Text(
                            context.l10n.tr(
                              '查看应用和第三方组件许可证',
                              en: 'View app and third-party component licenses',
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const OpenSourceLicenseScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    key: const ValueKey('about-disclaimer'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer.withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      context.l10n.tr(
                        '本应用是 JMComic3 Flutter 的非官方修改分支，'
                        '与上游项目维护者无隶属关系。',
                        en: 'This app is an unofficial fork of JMComic3 '
                            'Flutter and is not affiliated with its upstream '
                            'maintainers.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutHeader extends StatelessWidget {
  final String version;

  const _AboutHeader({required this.version});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 380;
    final icon = const AppIcon(size: 64, borderRadius: 16);
    final details = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          'JMComic3 Mod',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.tr(
            'Flutter + Rust 漫画阅读与管理客户端',
            en: 'Flutter + Rust comic reader and manager',
          ),
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 9),
        VersionBadged(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: .62),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              version,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
    return Container(
      key: const ValueKey('about-app-info'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: .88),
            scheme.tertiaryContainer.withValues(alpha: .58),
          ],
        ),
      ),
      child: compact
          ? Column(children: [icon, const SizedBox(height: 12), details])
          : Row(
              children: [
                icon,
                const SizedBox(width: 15),
                Expanded(child: details),
              ],
            ),
    );
  }
}
