import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/app_log.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'components/app_back_button.dart';
import 'components/right_click_pop.dart';

class RuntimeLogScreen extends StatefulWidget {
  const RuntimeLogScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _RuntimeLogScreenState();
}

class _RuntimeLogScreenState extends State<RuntimeLogScreen> {
  late List<AppLogEntry> _entries;
  StreamSubscription<List<AppLogEntry>>? _subscription;
  var _errorsOnly = false;

  List<AppLogEntry> get _visibleEntries {
    final entries = _errorsOnly
        ? _entries.where((entry) => entry.level == AppLogLevel.error)
        : _entries;
    return entries.toList().reversed.toList();
  }

  @override
  void initState() {
    _entries = AppLog.entries.toList();
    _subscription = AppLog.changes.listen((entries) {
      if (mounted) {
        setState(() => _entries = entries);
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = _visibleEntries;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.l10n.tr('运行日志', en: 'Runtime logs')),
        actions: [
          IconButton(
            tooltip: context.l10n.tr('复制日志', en: 'Copy logs'),
            onPressed: _entries.isEmpty ? null : () => _copyLogs(context),
            icon: const Icon(Icons.copy_all_rounded),
          ),
          IconButton(
            tooltip: context.l10n.tr('导出日志', en: 'Export logs'),
            onPressed: _entries.isEmpty ? null : () => _exportLogs(context),
            icon: const Icon(Icons.save_alt_rounded),
          ),
          IconButton(
            tooltip: context.l10n.tr('清空日志', en: 'Clear logs'),
            onPressed: _entries.isEmpty ? null : () => _clearLogs(context),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: .5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.article_outlined,
                              size: 20,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.tr(
                                      '最近 ${_entries.length} 条记录',
                                      en: '${_entries.length} recent entries',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    context.l10n.tr(
                                      '仅保留本次运行日志，敏感信息会自动隐藏。',
                                      en: 'Kept for this session only; sensitive values are redacted.',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilterChip(
                            key: const ValueKey('runtime-log-errors-only'),
                            selected: _errorsOnly,
                            showCheckmark: false,
                            selectedColor:
                                scheme.errorContainer.withValues(alpha: .52),
                            backgroundColor: scheme.surfaceContainerHighest,
                            side: BorderSide(
                              color: _errorsOnly
                                  ? scheme.error.withValues(alpha: .42)
                                  : scheme.outlineVariant.withValues(alpha: .5),
                            ),
                            shape: const StadiumBorder(),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onSelected: (selected) {
                              setState(() => _errorsOnly = selected);
                            },
                            label: Text(
                              context.l10n.tr('仅错误', en: 'Errors only'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _errorsOnly
                                    ? scheme.onErrorContainer
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                            avatar: Icon(
                              Icons.error_outline_rounded,
                              size: 16,
                              color: _errorsOnly
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? _EmptyLogs(errorsOnly: _errorsOnly)
                      : ListView.separated(
                          key: const ValueKey('runtime-log-list'),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 7),
                          itemBuilder: (context, index) {
                            return _LogEntryCard(entry: entries[index]);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyLogs(BuildContext context) {
    copyToClipBoard(context, AppLog.exportText());
  }

  Future<void> _exportLogs(BuildContext context) async {
    try {
      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      final fileName = 'jmcomic3-log-${now.year}${two(now.month)}'
          '${two(now.day)}-${two(now.hour)}${two(now.minute)}.log';
      final path = await methods.saveTextDocument(
        fileName: fileName,
        content: AppLog.exportText(),
        mimeType: 'text/plain',
      );
      if (!context.mounted) return;
      if (path == null || path.isEmpty) {
        defaultToast(
          context,
          context.l10n.tr('当前平台暂不支持导出日志', en: 'Log export is unavailable'),
        );
        return;
      }
      defaultToast(
        context,
        context.l10n.tr('日志已导出', en: 'Logs exported'),
      );
    } catch (error) {
      if (context.mounted) {
        defaultToast(
          context,
          context.l10n.tr('导出日志失败：$error', en: 'Export failed: $error'),
        );
      }
    }
  }

  Future<void> _clearLogs(BuildContext context) async {
    final confirmed = await confirmDialog(
      context,
      context.l10n.tr('清空运行日志', en: 'Clear runtime logs'),
      context.l10n.tr(
        '清空后无法恢复，确定继续吗？',
        en: 'Cleared logs cannot be recovered. Continue?',
      ),
    );
    if (!confirmed) return;
    AppLog.clear();
  }
}

class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard({required this.entry});

  final AppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (entry.level) {
      AppLogLevel.info => scheme.onSurfaceVariant,
      AppLogLevel.warning => scheme.tertiary,
      AppLogLevel.error => scheme.error,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: entry.level == AppLogLevel.error
            ? scheme.errorContainer.withValues(alpha: .28)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: SelectableText(
        entry.formatted,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.45,
        ),
      ),
    );
  }
}

class _EmptyLogs extends StatelessWidget {
  const _EmptyLogs({required this.errorsOnly});

  final bool errorsOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              errorsOnly ? Icons.verified_rounded : Icons.receipt_long_outlined,
              size: 42,
              color: scheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              errorsOnly
                  ? context.l10n.tr('没有错误日志', en: 'No error logs')
                  : context.l10n.tr('暂时没有日志', en: 'No logs yet'),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              errorsOnly
                  ? context.l10n.tr(
                      '当前运行期间没有记录到错误。',
                      en: 'No errors were recorded in this session.',
                    )
                  : context.l10n.tr(
                      '运行过程中产生的记录会显示在这里。',
                      en: 'Runtime events will appear here.',
                    ),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
