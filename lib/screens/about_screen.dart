import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/badge.dart';

import 'components/app_icon.dart';
import 'components/right_click_pop.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AboutState();
}

class _AboutState extends State<AboutScreen> {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (updatesTemporarilyDisabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _silentCheck());
  }

  Future<void> _silentCheck() async {
    if (!mounted) return;
    setState(() => _checking = true);
    try {
      await silentCheckNewVersion();
    } catch (_) {
      // The manual action reports network errors; startup stays quiet.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _manualCheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await manualCheckNewVersion(context);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('about-update-page'),
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(context.l10n.about),
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AboutHero(version: currentVersion()),
                  const SizedBox(height: 12),
                  if (updatesTemporarilyDisabled)
                    const _UpdatesDisabledCard()
                  else ...[
                    _UpdateStatusCard(
                      checking: _checking,
                      onCheck: _manualCheck,
                      onOpenRelease: () => openUrl(latestDownloadUrl()),
                    ),
                    if (latestVersion != null) ...[
                      const SizedBox(height: 12),
                      _ReleaseNotesCard(
                        notes: latestVersionInfo(),
                        onCheck: _manualCheck,
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  const _ProjectCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutHero extends StatelessWidget {
  final String version;

  const _AboutHero({required this.version});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 19;
    final icon = Container(
      key: const ValueKey('about-app-icon'),
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .2),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: const AppIcon(size: 64, borderRadius: 16),
    );
    final details = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          'JMComic3 Mod',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: theme.textTheme.titleLarge?.copyWith(
            color: scheme.onPrimaryContainer,
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
            color: scheme.onPrimaryContainer.withValues(alpha: .7),
          ),
        ),
        const SizedBox(height: 9),
        VersionBadged(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: .58),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              version,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.tertiaryContainer.withValues(alpha: .72),
          ],
        ),
        border: Border.all(
          color: scheme.primary.withValues(alpha: .12),
        ),
      ),
      child: compact
          ? Column(
              children: [
                icon,
                const SizedBox(height: 13),
                details,
              ],
            )
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

class _UpdateStatusCard extends StatelessWidget {
  final bool checking;
  final VoidCallback onCheck;
  final VoidCallback onOpenRelease;

  const _UpdateStatusCard({
    required this.checking,
    required this.onCheck,
    required this.onOpenRelease,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasUpdate = latestVersion != null;
    final statusColor = hasUpdate ? scheme.primary : Colors.green;
    // The repository can lag behind a local build. Never label an older
    // online release as the latest version.
    final latest = hasUpdate ? latestVersion! : currentVersion();

    return Container(
      key: const ValueKey('about-update-status'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: statusColor.withValues(alpha: .2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasUpdate
                      ? Icons.system_update_alt_rounded
                      : Icons.verified_rounded,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      checking
                          ? context.l10n
                              .tr('正在检查更新', en: 'Checking for updates')
                          : hasUpdate
                              ? context.l10n.tr(
                                  '发现新版本 $latest',
                                  en: 'New version $latest is available',
                                )
                              : context.l10n.tr(
                                  '当前已是最新版本',
                                  en: 'You are up to date',
                                ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasUpdate
                          ? context.l10n.tr(
                              '可前往发布页面下载新版本',
                              en: 'Open the release page to download it',
                            )
                          : context.l10n.tr(
                              '更新来自当前 Fork 的 GitHub Releases',
                              en: 'Updates come from this fork’s GitHub Releases',
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              FilledButton.icon(
                key: const ValueKey('about-check-update'),
                onPressed: checking ? null : onCheck,
                icon: checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  checking
                      ? context.l10n.tr('检查中...', en: 'Checking...')
                      : context.l10n.checkUpdate,
                ),
              ),
              if (hasUpdate)
                OutlinedButton.icon(
                  key: const ValueKey('about-download-update'),
                  onPressed: onOpenRelease,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(
                    context.l10n.goToDownloadPage,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _VersionComparison(
            current: currentVersion(),
            latest: latest,
            hasUpdate: hasUpdate,
          ),
        ],
      ),
    );
  }
}

class _VersionComparison extends StatelessWidget {
  final String current;
  final String latest;
  final bool hasUpdate;

  const _VersionComparison({
    required this.current,
    required this.latest,
    required this.hasUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final currentTile = _VersionTile(
          key: const ValueKey('about-current-version'),
          label: context.l10n.currentVersion,
          version: current,
          highlighted: false,
        );
        final latestTile = _VersionTile(
          key: const ValueKey('about-latest-version'),
          label: context.l10n.latestVersion,
          version: latest,
          highlighted: hasUpdate,
        );
        return Row(
          children: [
            Expanded(child: currentTile),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.east_rounded, size: 16),
            ),
            Expanded(child: latestTile),
          ],
        );
      },
    );
  }
}

class _VersionTile extends StatelessWidget {
  final String label;
  final String version;
  final bool highlighted;

  const _VersionTile({
    super.key,
    required this.label,
    required this.version,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primaryContainer.withValues(alpha: .55)
            : scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                version,
                maxLines: 1,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: highlighted ? scheme.onPrimaryContainer : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseNotesCard extends StatelessWidget {
  final String? notes;
  final VoidCallback onCheck;

  const _ReleaseNotesCard({required this.notes, required this.onCheck});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = (notes ?? '').trim().isNotEmpty;
    final normalized = available ? _normalizeReleaseNotes(notes!) : '';
    return Container(
      key: const ValueKey('about-release-notes'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(Icons.notes_rounded, size: 19, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.updateContent,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          if (available)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: MarkdownBody(
                data: normalized,
                selectable: true,
                onTapLink: (_, href, __) {
                  if (href != null && href.trim().isNotEmpty) {
                    openUrl(href);
                  }
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: Column(
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 34,
                    color: scheme.onSurfaceVariant.withValues(alpha: .65),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    context.l10n.updateContentUnavailable,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onCheck,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(context.l10n.checkUpdate),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: .4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: const ValueKey('about-project-link'),
        onTap: () => openUrl(releasePageUrl),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            Icons.code_rounded,
            size: 20,
            color: scheme.primary,
          ),
        ),
        title: Text(
          context.l10n.tr('项目主页', en: 'Project page'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: const Text('khxw/JMcomic3-flutter'),
        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
      ),
    );
  }
}

class _UpdatesDisabledCard extends StatelessWidget {
  const _UpdatesDisabledCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.system_update_alt_rounded,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.tr(
                '更新检查已暂时关闭',
                en: 'Update checks are temporarily disabled',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _normalizeReleaseNotes(String input) {
  final lines = input.trim().split('\n');
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  if (lines.isNotEmpty && lines.first.trimLeft().startsWith('# ')) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  return lines.join('\n').trim();
}
