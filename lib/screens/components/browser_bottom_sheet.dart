import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/configs/auto_clean.dart';
import 'package:jmcomic3/configs/network_api_host.dart';
import 'package:jmcomic3/configs/network_cdn_host.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class BrowserBottomSheetAction extends StatelessWidget {
  const BrowserBottomSheetAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.tr('浏览设置', en: 'Browse settings'),
      onPressed: () => _displayBrowserBottomSheet(context),
      icon: const Icon(Icons.menu_rounded),
    );
  }
}

Future<void> _displayBrowserBottomSheet(BuildContext context) async {
  final scheme = Theme.of(context).colorScheme;
  final height = MediaQuery.sizeOf(context).height;
  await showMaterialModalBottomSheet<void>(
    context: context,
    backgroundColor: scheme.surface,
    barrierColor: Colors.black.withValues(alpha: .34),
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        top: false,
        child: SizedBox(
          height: math.min(440, height * .68),
          child: const _BrowserBottomSheet(),
        ),
      );
    },
  );
}

class _BrowserBottomSheet extends StatefulWidget {
  const _BrowserBottomSheet();

  @override
  State<StatefulWidget> createState() => _BrowserBottomSheetState();
}

class _BrowserBottomSheetState extends State<_BrowserBottomSheet> {
  bool _manualCleaning = false;

  bool get _cleaning => _manualCleaning || cacheCleaningInProgress;

  @override
  void initState() {
    currentPagerControllerModeEvent.subscribe(_setState);
    currentPagerViewModeEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    currentPagerControllerModeEvent.unsubscribe(_setState);
    currentPagerViewModeEvent.unsubscribe(_setState);
    super.dispose();
  }

  void _setState(_) {
    if (mounted) setState(() {});
  }

  Future<void> _runManualClean() async {
    if (_cleaning) return;
    setState(() => _manualCleaning = true);
    defaultToast(
      context,
      context.l10n.tr('开始清理缓存', en: 'Start cleaning cache'),
    );
    final result = await cleanCache();
    if (!mounted) return;
    setState(() => _manualCleaning = false);
    if (result.success) {
      defaultToast(
        context,
        context.l10n.tr(
          '清理完成 (${result.duration.inMilliseconds}ms)',
          en: 'Cleanup complete (${result.duration.inMilliseconds}ms)',
        ),
      );
      return;
    }
    debugPrient('clean cache failed: ${result.error}');
    defaultToast(
      context,
      context.l10n.tr(
        '清理失败，请稍后重试',
        en: 'Cleanup failed, please try again later',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      key: const ValueKey('browser-settings-sheet'),
      children: [
        const SizedBox(height: 9),
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.outlineVariant.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 10, 8),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: scheme.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.tr('浏览设置', en: 'Browse settings'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      context.l10n.tr(
                        '布局、缓存与网络',
                        en: 'Layout, cache and network',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
            children: [
              _SectionLabel(
                icon: Icons.dashboard_customize_outlined,
                label: context.l10n.tr('布局与显示', en: 'Layout & display'),
              ),
              const SizedBox(height: 9),
              LayoutBuilder(
                builder: (context, constraints) {
                  final spacing = constraints.maxWidth >= 520 ? 12.0 : 10.0;
                  final width = (constraints.maxWidth - spacing) / 2;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      _ActionTile(
                        width: width,
                        actionKey: const ValueKey('browser-menu-view-mode'),
                        icon: Icons.view_quilt_rounded,
                        title: context.l10n.tr('浏览布局', en: 'View mode'),
                        value: currentPagerViewModeName(context),
                        onPressed: () async {
                          await choosePagerViewMode(context);
                          setState(() {});
                        },
                      ),
                      _ActionTile(
                        width: width,
                        actionKey: const ValueKey('browser-menu-controller'),
                        icon: Icons.view_day_outlined,
                        title: context.l10n.tr('翻页方式', en: 'Paging mode'),
                        value: currentPagerControllerModeName(context),
                        onPressed: () async {
                          await choosePagerControllerMode(context);
                          setState(() {});
                        },
                      ),
                      _ActionTile(
                        width: width,
                        actionKey: const ValueKey('browser-menu-cover-rate'),
                        icon: Icons.aspect_ratio_rounded,
                        title: context.l10n.tr('封面比例', en: 'Cover ratio'),
                        value: pagerCoverRateName(
                          currentPagerCoverRate,
                          context,
                        ),
                        onPressed: () async {
                          await choosePagerCoverRate(context);
                          setState(() {});
                        },
                      ),
                      _ActionTile(
                        width: width,
                        actionKey: const ValueKey('browser-menu-columns'),
                        icon: Icons.view_column_rounded,
                        title: context.l10n.tr('每行数量', en: 'Columns'),
                        value: context.l10n.tr(
                          '$pagerColumnNumber 列',
                          en: '$pagerColumnNumber columns',
                        ),
                        onPressed: () async {
                          await choosePagerColumnCount(context);
                          setState(() {});
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              _SectionLabel(
                icon: Icons.storage_rounded,
                label: context.l10n.tr('缓存与网络', en: 'Cache & network'),
              ),
              const SizedBox(height: 9),
              LayoutBuilder(
                builder: (context, constraints) {
                  final spacing = constraints.maxWidth >= 520 ? 12.0 : 10.0;
                  final width = (constraints.maxWidth - spacing) / 2;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      _ActionTile(
                        width: width,
                        actionKey: const ValueKey('browser-menu-clean'),
                        icon: _cleaning
                            ? Icons.cleaning_services_outlined
                            : Icons.cleaning_services_rounded,
                        title: _cleaning
                            ? context.l10n.tr('清理中...', en: 'Cleaning...')
                            : context.l10n.tr('清理缓存', en: 'Clean cache'),
                        value: context.l10n.tr('立即执行', en: 'Run now'),
                        onPressed: _cleaning ? null : _runManualClean,
                      ),
                      _ActionTile(
                        width: width,
                        actionKey: const ValueKey('browser-menu-auto-clean'),
                        icon: Icons.auto_delete_outlined,
                        title: context.l10n.tr('自动清理', en: 'Auto clean'),
                        value: autoCleanNameOf(context),
                        onPressed: () async {
                          await chooseAutoClean(context);
                          setState(() {});
                        },
                      ),
                      _ActionTile(
                        width: width,
                        actionKey: const ValueKey('browser-menu-api-host'),
                        icon: Icons.dns_outlined,
                        title: context.l10n.tr('API 线路', en: 'API route'),
                        value: currentApiHostName,
                        onPressed: () async {
                          await chooseApiHost(context);
                          setState(() {});
                        },
                      ),
                      _ActionTile(
                        width: width,
                        actionKey: const ValueKey('browser-menu-cdn-host'),
                        icon: Icons.cloud_outlined,
                        title: context.l10n.tr('图片线路', en: 'Image route'),
                        value: currentCdnHostName,
                        onPressed: () async {
                          await chooseCdnHost(context);
                          setState(() {});
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 7),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final double width;
  final Key actionKey;
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onPressed;

  const _ActionTile({
    required this.width,
    required this.actionKey,
    required this.icon,
    required this.title,
    required this.value,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null;
    return SizedBox(
      width: width,
      child: Material(
        key: actionKey,
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(
                      alpha: enabled ? .11 : .05,
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: enabled
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: .45),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: enabled
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant.withValues(alpha: .55),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: scheme.onSurfaceVariant.withValues(alpha: .55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
