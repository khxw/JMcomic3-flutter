import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'components/images.dart';

class DownloadExportSelectionView extends StatelessWidget {
  final List<DownloadAlbum> albums;
  final Set<int> selected;
  final String modeLabel;
  final ValueChanged<DownloadAlbum> onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onContinue;

  const DownloadExportSelectionView({
    super.key,
    required this.albums,
    required this.selected,
    required this.modeLabel,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClear,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final pageInset = MediaQuery.sizeOf(context).width >= 760 ? 24.0 : 14.0;
    final imageCount =
        albums.fold<int>(0, (total, album) => total + album.imageCount);

    return Stack(
      key: const ValueKey('batch-export-page'),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView.builder(
              key: const ValueKey('batch-export-list'),
              padding: EdgeInsets.fromLTRB(pageInset, 10, pageInset, 126),
              itemCount: albums.isEmpty ? 2 : albums.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SelectionSummary(
                      modeLabel: modeLabel,
                      selectedCount: selected.length,
                      totalCount: albums.length,
                      imageCount: imageCount,
                      allSelected:
                          albums.isNotEmpty && selected.length == albums.length,
                      onSelectAll: onSelectAll,
                      onClear: onClear,
                    ),
                  );
                }
                if (albums.isEmpty) {
                  return const _ExportEmptyState();
                }
                final album = albums[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _ExportComicCard(
                    album: album,
                    selected: selected.contains(album.id),
                    onTap: () => onToggle(album),
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.fromLTRB(pageInset, 0, pageInset, 10),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _SelectionActionBar(
                  selectedCount: selected.length,
                  totalCount: albums.length,
                  onClear: onClear,
                  onContinue: selected.isEmpty ? null : onContinue,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectionSummary extends StatelessWidget {
  final String modeLabel;
  final int selectedCount;
  final int totalCount;
  final int imageCount;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  const _SelectionSummary({
    required this.modeLabel,
    required this.selectedCount,
    required this.totalCount,
    required this.imageCount,
    required this.allSelected,
    required this.onSelectAll,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('batch-export-summary'),
      padding: const EdgeInsets.fromLTRB(15, 14, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: .72),
            scheme.tertiaryContainer.withValues(alpha: .42),
          ],
        ),
        border: Border.all(
          color: scheme.primary.withValues(alpha: .14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedCount == 0
                          ? context.l10n.tr(
                              '选择要导出的漫画',
                              en: 'Choose comics to export',
                            )
                          : context.l10n.tr(
                              '已选择 $selectedCount 本',
                              en: '$selectedCount selected',
                            ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.tr(
                        '$modeLabel · 共 $totalCount 本 / $imageCount 张图片',
                        en: '$modeLabel · $totalCount comics / $imageCount images',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(alpha: .7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton.icon(
                onPressed: totalCount == 0 ? null : onSelectAll,
                icon: Icon(
                  allSelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                  size: 18,
                ),
                label: Text(
                  allSelected
                      ? context.l10n.tr('取消全选', en: 'Clear all')
                      : context.l10n.tr('全选', en: 'Select all'),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onPrimaryContainer,
                  backgroundColor: scheme.surface.withValues(alpha: .44),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (selectedCount > 0)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(context.l10n.tr('清除选择', en: 'Clear selection')),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onPrimaryContainer,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportComicCard extends StatelessWidget {
  final DownloadAlbum album;
  final bool selected;
  final VoidCallback onTap;

  const _ExportComicCard({
    required this.album,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 350 ||
        MediaQuery.textScalerOf(context).scale(14) > 19;
    final coverWidth = compact ? 54.0 : 62.0;
    final status = _ExportStatus.of(context, album);
    final progress = album.downloadProgress;

    return Semantics(
      button: true,
      selected: selected,
      label: album.name,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: .3)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: .58)
                : scheme.outlineVariant.withValues(alpha: .42),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('batch-export-album-${album.id}'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(top: 2, right: 9),
                    decoration: BoxDecoration(
                      color: selected ? scheme.primary : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.outline.withValues(alpha: .65),
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: scheme.onPrimary,
                          )
                        : null,
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: JM3x4Cover(
                      comicId: album.id,
                      width: coverWidth,
                      height: coverWidth * 4 / 3,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                album.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            _ExportStatusPill(status: status),
                          ],
                        ),
                        if (album.authorLabel.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            album.authorLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.image_outlined,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                context.l10n.tr(
                                  '${album.dledImageCount} / ${album.imageCount} 张',
                                  en: '${album.dledImageCount} / ${album.imageCount} images',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (progress != null)
                              Text(
                                '${(progress * 100).round()}%',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: status.color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        if (progress != null) ...[
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              color: status.color,
                              backgroundColor:
                                  status.color.withValues(alpha: .12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportStatus {
  final String label;
  final Color color;

  const _ExportStatus(this.label, this.color);

  factory _ExportStatus.of(BuildContext context, DownloadAlbum album) {
    if (album.isDownloaded) {
      return _ExportStatus(
        context.l10n.tr('已下载', en: 'Downloaded'),
        Colors.green,
      );
    }
    if (album.isFailed) {
      return _ExportStatus(
        context.l10n.tr('失败', en: 'Failed'),
        Theme.of(context).colorScheme.error,
      );
    }
    if (album.isDeleting) {
      return _ExportStatus(
        context.l10n.tr('删除中', en: 'Deleting'),
        Colors.orange,
      );
    }
    return _ExportStatus(
      context.l10n.tr('下载中', en: 'Downloading'),
      Colors.blue,
    );
  }
}

class _ExportStatusPill extends StatelessWidget {
  final _ExportStatus status;

  const _ExportStatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: status.color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ExportEmptyState extends StatelessWidget {
  const _ExportEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 46),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .38),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 42,
            color: scheme.onSurfaceVariant.withValues(alpha: .7),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.tr('暂无可导出的漫画', en: 'No comics to export'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            context.l10n.tr(
              '下载完成后，漫画会显示在这里。',
              en: 'Downloaded comics will appear here.',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionActionBar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onClear;
  final VoidCallback? onContinue;

  const _SelectionActionBar({
    required this.selectedCount,
    required this.totalCount,
    required this.onClear,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final compact = constraints.maxWidth < 370 || textScale > 1.25;
        final summary = Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.checklist_rounded,
                size: 20,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.tr(
                      '已选择 $selectedCount 本',
                      en: '$selectedCount selected',
                    ),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    totalCount == 0
                        ? context.l10n.tr('没有可导出内容', en: 'Nothing to export')
                        : context.l10n.tr(
                            '共 $totalCount 本可用',
                            en: '$totalCount available',
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selectedCount > 0)
              IconButton(
                tooltip: context.l10n.tr('清除选择', en: 'Clear selection'),
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
          ],
        );
        final action = FilledButton.icon(
          key: const ValueKey('batch-export-continue'),
          onPressed: onContinue,
          icon: const Icon(Icons.arrow_forward_rounded, size: 19),
          label: Text(context.l10n.tr('下一步', en: 'Next')),
          style: FilledButton.styleFrom(
            minimumSize: Size(compact ? double.infinity : 122, 46),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
        );

        return Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: .97),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .13),
                blurRadius: 20,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    summary,
                    const SizedBox(height: 9),
                    action,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 12),
                    action,
                  ],
                ),
        );
      },
    );
  }
}

class ExportPageIntro extends StatelessWidget {
  final int itemCount;
  final bool includesIncomplete;

  const ExportPageIntro({
    super.key,
    required this.itemCount,
    required this.includesIncomplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: .7),
            scheme.tertiaryContainer.withValues(alpha: .38),
          ],
        ),
        border: Border.all(
          color: scheme.primary.withValues(alpha: .13),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              includesIncomplete
                  ? Icons.inventory_2_outlined
                  : Icons.archive_outlined,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr(
                    '准备导出 $itemCount 本漫画',
                    en: 'Exporting $itemCount comics',
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  includesIncomplete
                      ? context.l10n.tr(
                          '支持导出尚未下载完成的章节',
                          en: 'Includes chapters from unfinished downloads',
                        )
                      : context.l10n.tr(
                          '选择一种格式开始导出',
                          en: 'Choose a format to begin',
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: .7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExportSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;

  const ExportSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

class ExportFormatTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color? accent;
  final VoidCallback? onPressed;

  const ExportFormatTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onPressed,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = accent ?? scheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  badge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExportProgressPanel extends StatelessWidget {
  final String label;
  final int itemCount;

  const ExportProgressPanel({
    super.key,
    required this.label,
    required this.itemCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .4),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.tr(
                    '正在处理 $itemCount 本漫画，请勿关闭页面',
                    en: 'Processing $itemCount comics. Keep this page open.',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ExportResultPanel extends StatelessWidget {
  final bool success;
  final String title;
  final String message;
  final VoidCallback onReset;

  const ExportResultPanel({
    super.key,
    required this.success,
    required this.title,
    required this.message,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = success ? Colors.green : scheme.error;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: .2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    success
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 31,
                    color: color,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  message,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 17),
                FilledButton.tonalIcon(
                  onPressed: onReset,
                  icon: Icon(
                    success ? Icons.done_rounded : Icons.arrow_back_rounded,
                  ),
                  label: Text(
                    success
                        ? context.l10n.tr('完成', en: 'Done')
                        : context.l10n.tr(
                            '返回格式列表',
                            en: 'Back to formats',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
