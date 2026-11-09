import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'components/app_back_button.dart';
import 'components/images.dart';

class ImageCacheDay {
  const ImageCacheDay({
    required this.date,
    required this.files,
    required this.bytes,
  });

  final String date;
  final int files;
  final int bytes;

  factory ImageCacheDay.fromJson(Map<String, dynamic> json) {
    return ImageCacheDay(
      date: '${json['date'] ?? ''}',
      files: int.tryParse('${json['files'] ?? 0}') ?? 0,
      bytes: int.tryParse('${json['bytes'] ?? 0}') ?? 0,
    );
  }
}

class ImageCacheCleanupScreen extends StatefulWidget {
  const ImageCacheCleanupScreen({super.key});

  @override
  State<ImageCacheCleanupScreen> createState() =>
      _ImageCacheCleanupScreenState();
}

class _ImageCacheCleanupScreenState extends State<ImageCacheCleanupScreen> {
  List<ImageCacheDay> _days = const [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _clearing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await methods.imageCacheDays();
      final rawDays = response['days'];
      final days = rawDays is List
          ? rawDays
              .whereType<Map>()
              .map(
                (item) => ImageCacheDay.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((day) => day.date.isNotEmpty)
              .toList(growable: false)
          : <ImageCacheDay>[];
      if (!mounted) return;
      setState(() {
        _days = days;
        _selected.removeWhere(
          (date) => !days.any((day) => day.date == date),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _clearSelected() async {
    if (_selected.isEmpty || _clearing) return;
    final selectedDays =
        _days.where((day) => _selected.contains(day.date)).toList();
    final selectedBytes = selectedDays.fold<int>(
      0,
      (total, day) => total + day.bytes,
    );
    final selectedFiles = selectedDays.fold<int>(
      0,
      (total, day) => total + day.files,
    );
    final confirmed = await confirmDialog(
      context,
      context.l10n.tr('清理图片缓存', en: 'Clear image cache'),
      context.l10n.tr(
        '将删除所选日期的 $selectedFiles 个缓存文件（${_formatBytes(selectedBytes)}）。'
        '不会影响下载漫画、书架和阅读记录。',
        en: 'Delete $selectedFiles cached files (${_formatBytes(selectedBytes)}) '
            'from the selected dates. Downloaded comics, bookshelf items, and '
            'reading history will not be affected.',
      ),
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearing = true);
    try {
      final result = await methods.clearImageCacheDays(_selected.toList());
      clearAllImageMemoryCaches();
      if (!mounted) return;
      final deletedFiles = int.tryParse('${result['deleted_files'] ?? 0}') ?? 0;
      final deletedBytes = int.tryParse('${result['deleted_bytes'] ?? 0}') ?? 0;
      _selected.clear();
      await _load();
      if (!mounted) return;
      defaultToast(
        context,
        context.l10n.tr(
          '已清理 $deletedFiles 个文件（${_formatBytes(deletedBytes)}）',
          en: 'Removed $deletedFiles files (${_formatBytes(deletedBytes)})',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      defaultToast(
        context,
        context.l10n.tr(
          '图片缓存清理失败：$error',
          en: 'Could not clear image cache: $error',
        ),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedBytes = _days
        .where((day) => _selected.contains(day.date))
        .fold<int>(0, (total, day) => total + day.bytes);
    return Scaffold(
      key: const ValueKey('image-cache-cleanup-page'),
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.l10n.tr('图片缓存清理', en: 'Image cache cleanup')),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _buildBody(context, scheme),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('image-cache-clear-selected'),
                onPressed:
                    _selected.isEmpty || _clearing ? null : _clearSelected,
                icon: _clearing
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_sweep_outlined),
                label: Text(
                  _selected.isEmpty
                      ? context.l10n.tr('选择要清理的日期', en: 'Select dates')
                      : context.l10n.tr(
                          '清理所选 ${_selected.length} 天'
                          '（${_formatBytes(selectedBytes)}）',
                          en: 'Clear ${_selected.length} day(s) '
                              '(${_formatBytes(selectedBytes)})',
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 140),
          Icon(Icons.error_outline_rounded, size: 34, color: scheme.error),
          const SizedBox(height: 12),
          Text(
            context.l10n.tr('图片缓存读取失败', en: 'Could not read image cache'),
            textAlign: TextAlign.center,
          ),
          Center(
            child: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.l10n.tr('重试', en: 'Retry')),
            ),
          ),
        ],
      );
    }
    if (_days.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 140),
          Icon(
            Icons.photo_library_outlined,
            size: 38,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.tr('没有可清理的图片缓存', en: 'No image cache to clear'),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    final allSelected = _selected.length == _days.length;
    return ListView(
      key: const ValueKey('image-cache-date-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.tr(
                    '按文件修改日期统计。只清理图片缓存，不清理已下载漫画、书架和阅读记录。',
                    en: 'Grouped by file modification date. Only image cache is '
                        'removed; downloaded comics, bookshelf items, and reading '
                        'history are kept.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('image-cache-select-all'),
            onPressed: () {
              setState(() {
                if (allSelected) {
                  _selected.clear();
                } else {
                  _selected
                    ..clear()
                    ..addAll(_days.map((day) => day.date));
                }
              });
            },
            child: Text(
              allSelected
                  ? context.l10n.tr('取消全选', en: 'Clear selection')
                  : context.l10n.tr('全选', en: 'Select all'),
            ),
          ),
        ),
        for (final day in _days)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: CheckboxListTile(
                key: ValueKey('image-cache-day-${day.date}'),
                value: _selected.contains(day.date),
                onChanged: (selected) {
                  setState(() {
                    if (selected == true) {
                      _selected.add(day.date);
                    } else {
                      _selected.remove(day.date);
                    }
                  });
                },
                secondary: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.calendar_today_outlined,
                    size: 19,
                    color: scheme.primary,
                  ),
                ),
                title: Text(
                  _dateLabel(context, day.date),
                  style: themeTextStyle(context, bold: true),
                ),
                subtitle: Text(
                  context.l10n.tr(
                    '${day.files} 个文件 · ${_formatBytes(day.bytes)}',
                    en: '${day.files} files · ${_formatBytes(day.bytes)}',
                  ),
                ),
                controlAffinity: ListTileControlAffinity.trailing,
              ),
            ),
          ),
      ],
    );
  }

  TextStyle? themeTextStyle(BuildContext context, {bool bold = false}) {
    return Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: bold ? FontWeight.w700 : null,
        );
  }

  String _dateLabel(BuildContext context, String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '${date.month}月${date.day}日'
        : value;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}
