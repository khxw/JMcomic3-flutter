import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../../basic/methods.dart';
import 'images.dart';

class ComicDownloadCard extends StatelessWidget {
  final DownloadAlbum comic;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool highlighted;

  const ComicDownloadCard(
    this.comic, {
    Key? key,
    this.onTap,
    this.onLongPress,
    this.highlighted = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = _DownloadCardStatus.of(context, comic);
    final progress = comic.downloadProgress;
    final compact = MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 19;
    final coverWidth = compact ? 66.0 : 76.0;
    final percent = progress == null ? null : '${(progress * 100).round()}%';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Semantics(
        button: onTap != null,
        label: context.l10n.tr(
          '${comic.name}，${status.label}',
          en: '${comic.name}, ${status.label}',
        ),
        child: Material(
          key: ValueKey('download-card-${comic.id}'),
          color: Color.alphaBlend(
            (highlighted ? scheme.primary : status.color)
                .withValues(alpha: highlighted ? .075 : .035),
            scheme.surfaceContainerLow,
          ),
          elevation: highlighted ? 1.5 : 0,
          shadowColor: scheme.primary.withValues(alpha: .2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: highlighted
                  ? scheme.primary.withValues(alpha: .65)
                  : status.color.withValues(
                      alpha: comic.isFailed ? .3 : .16,
                    ),
              width: highlighted ? 1.4 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: .55),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .09),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: JM3x4Cover(
                        comicId: comic.id,
                        width: coverWidth,
                        height: coverWidth * 4 / 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          comic.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.28,
                          ),
                        ),
                        if (comic.authorLabel.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            comic.authorLabel,
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
                            _DownloadStatusPill(status: status),
                            const Spacer(),
                            if (percent != null)
                              Text(
                                percent,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: status.color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        if (progress != null) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: comic.isDeleting ? null : progress,
                              minHeight: 5,
                              color: status.color,
                              backgroundColor:
                                  status.color.withValues(alpha: .11),
                            ),
                          ),
                        ],
                        const SizedBox(height: 7),
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
                                  '${comic.dledImageCount} / ${comic.imageCount} 张图片',
                                  en: '${comic.dledImageCount} / ${comic.imageCount} images',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
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

class _DownloadCardStatus {
  final String label;
  final IconData icon;
  final Color color;

  const _DownloadCardStatus(this.label, this.icon, this.color);

  factory _DownloadCardStatus.of(BuildContext context, DownloadAlbum album) {
    final scheme = Theme.of(context).colorScheme;
    if (album.isQueuedOrDownloading) {
      if (album.dledImageCount > 0) {
        return _DownloadCardStatus(
          context.l10n.tr('下载中', en: 'Downloading'),
          Icons.downloading_rounded,
          scheme.primary,
        );
      }
      return _DownloadCardStatus(
        context.l10n.tr('队列中', en: 'Queued'),
        Icons.schedule_rounded,
        Colors.amber.shade700,
      );
    }
    if (album.isDownloaded) {
      return _DownloadCardStatus(
        context.l10n.tr('已下载', en: 'Downloaded'),
        Icons.check_circle_rounded,
        Colors.green.shade600,
      );
    }
    if (album.isFailed) {
      return _DownloadCardStatus(
        context.l10n.tr('下载失败', en: 'Failed'),
        Icons.error_rounded,
        scheme.error,
      );
    }
    if (album.isDeleting) {
      return _DownloadCardStatus(
        context.l10n.tr('删除中', en: 'Deleting'),
        Icons.delete_sweep_rounded,
        Colors.orange.shade700,
      );
    }
    return _DownloadCardStatus(
      context.l10n.tr('未知状态', en: 'Unknown status'),
      Icons.help_outline_rounded,
      scheme.onSurfaceVariant,
    );
  }
}

class _DownloadStatusPill extends StatelessWidget {
  final _DownloadCardStatus status;

  const _DownloadStatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 13, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: status.color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
