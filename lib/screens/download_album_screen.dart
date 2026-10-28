import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/basic/reader_pages.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/images.dart';

import 'comic_info_screen.dart';
import 'comic_reader_screen.dart';
import 'comic_search_screen.dart';
import 'components/app_back_button.dart';
import 'components/right_click_pop.dart';

class DownloadAlbumScreen extends StatefulWidget {
  final DownloadAlbum album;

  const DownloadAlbumScreen(this.album, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadAlbumScreenState();
}

class _DownloadAlbumScreenState extends State<DownloadAlbumScreen> {
  static const _autoRefreshInterval = Duration(seconds: 2);

  late DownloadAlbum _album;
  late Future<DownloadCreate?> _future;
  late Future<ViewLog?> _viewFuture;
  Timer? _autoRefreshTimer;
  bool _loadingAlbum = false;
  bool _taskRemoved = false;

  @override
  void initState() {
    super.initState();
    _album = widget.album;
    _future = methods.downloadById(_album.id);
    _viewFuture = methods.findViewLog(_album.id);
    _syncAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAlbum() async {
    if (_loadingAlbum) {
      _syncAutoRefresh();
      return;
    }
    _loadingAlbum = true;
    try {
      final album = await methods.downloadAlbumById(_album.id);
      if (!mounted) return;
      if (album == null) {
        _taskRemoved = true;
        Navigator.of(context).maybePop();
        return;
      }
      setState(() => _album = album);
    } catch (_) {
      // A temporary status refresh failure must not hide readable chapters.
    } finally {
      _loadingAlbum = false;
      if (mounted && !_taskRemoved) _syncAutoRefresh();
    }
  }

  Future<void> _reloadAll() async {
    if (!mounted) return;
    setState(() {
      _future = methods.downloadById(_album.id);
      _viewFuture = methods.findViewLog(_album.id);
    });
    try {
      await Future.wait([
        _refreshAlbum(),
        _future,
        _viewFuture,
      ]);
    } catch (_) {
      // The page owns retry states for task details and reading progress.
    }
  }

  void _syncAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    if (_taskRemoved || !_album.shouldAutoRefreshStatus) return;
    _autoRefreshTimer = Timer(_autoRefreshInterval, _refreshAlbum);
  }

  void _reloadViewLog() {
    if (!mounted) return;
    setState(() => _viewFuture = methods.findViewLog(_album.id));
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('download-detail-page'),
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: const AppBackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.tr('下载详情', en: 'Download details')),
            Text(
              _album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.tr('刷新', en: 'Refresh'),
            onPressed: _reloadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: context.l10n.tr('查看漫画详情', en: 'Comic details'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ComicInfoScreen(_album.id, null),
                ),
              );
            },
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: FutureBuilder<DownloadCreate?>(
        future: _future,
        builder: (context, snapshot) {
          final create = snapshot.data;
          return RefreshIndicator(
            onRefresh: _reloadAll,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.maxWidth > 920
                    ? (constraints.maxWidth - 920) / 2 + 16
                    : 16.0;
                final usableWidth = constraints.maxWidth - side * 2;
                final textScale =
                    MediaQuery.textScalerOf(context).scale(14) / 14;
                final columns = textScale > 1.35
                    ? 1
                    : usableWidth >= 680
                        ? 3
                        : 2;

                return CustomScrollView(
                  key: const ValueKey('download-detail-scroll'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(side, 10, side, 0),
                      sliver: SliverToBoxAdapter(
                        child: _DownloadHero(album: _album),
                      ),
                    ),
                    if (create != null && create.hasChapters)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 12, side, 0),
                        sliver: SliverToBoxAdapter(
                          child: _readingEntry(create),
                        ),
                      ),
                    if (_album.tagList.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 14, side, 0),
                        sliver: SliverToBoxAdapter(
                          child: _DownloadTags(tags: _album.tagList),
                        ),
                      ),
                    if (_album.description.trim().isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 12, side, 0),
                        sliver: SliverToBoxAdapter(
                          child: _DownloadDescription(
                            description: _album.description,
                          ),
                        ),
                      ),
                    if (snapshot.connectionState != ConnectionState.done)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 18, side, 0),
                        sliver: const SliverToBoxAdapter(
                          child: _DownloadStatusMessage.loading(),
                        ),
                      )
                    else if (snapshot.hasError || create == null)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 18, side, 0),
                        sliver: SliverToBoxAdapter(
                          child: _DownloadStatusMessage.error(
                            onRetry: _reloadAll,
                          ),
                        ),
                      )
                    else if (create.chapters.isEmpty)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 18, side, 0),
                        sliver: const SliverToBoxAdapter(
                          child: _DownloadStatusMessage.emptyChapters(),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 20, side, 10),
                        sliver: SliverToBoxAdapter(
                          child: _ChapterHeader(count: create.chapters.length),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 0, side, 28),
                        sliver: SliverGrid.builder(
                          key: const ValueKey('download-detail-chapters'),
                          itemCount: create.chapters.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            mainAxisExtent: textScale > 1.35 ? 88 : 76,
                          ),
                          itemBuilder: (context, index) {
                            final chapter = create.chapters[index];
                            return _ChapterTile(
                              chapter: chapter,
                              onTap: () => _push(create, chapter.id, 0),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _readingEntry(DownloadCreate create) {
    return FutureBuilder<ViewLog?>(
      future: _viewFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ReadEntryButton(
            label: context.l10n.tr('读取进度失败，点击重试', en: 'Retry reading progress'),
            icon: Icons.refresh_rounded,
            onPressed: _reloadViewLog,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return _ReadEntryButton(
            label: context.l10n.tr(
              '读取阅读进度',
              en: 'Loading reading progress',
            ),
            icon: Icons.hourglass_empty_rounded,
          );
        }

        final log = snapshot.data;
        final canContinue =
            log != null && create.containsChapterId(log.lastViewChapterId);
        final chapterId =
            canContinue ? log.lastViewChapterId : create.initialChapterId;
        final page =
            canContinue && log.lastViewPage >= 0 ? log.lastViewPage : 0;
        final chapter = create.chapterById(chapterId);
        final chapterTitle = chapter == null
            ? ''
            : chapter.name.trim().isEmpty
                ? chapter.sort
                : chapter.name;

        return _ReadEntryButton(
          label: canContinue
              ? context.l10n.tr('继续阅读', en: 'Continue reading')
              : context.l10n.tr('从头开始', en: 'Start from beginning'),
          detail: canContinue
              ? context.l10n.tr(
                  '$chapterTitle · 第 ${page + 1} 页',
                  en: '$chapterTitle · page ${page + 1}',
                )
              : chapterTitle,
          icon: Icons.play_arrow_rounded,
          onPressed: () => _push(create, chapterId, page),
        );
      },
    );
  }

  void _push(DownloadCreate create, int seriesId, int initRank) {
    if (!create.hasChapters || !create.containsChapterId(seriesId)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComicReaderScreen(
          comic: ComicBasic(
            id: create.album.id,
            author: create.album.author.join(" / "),
            description: create.album.description,
            name: create.album.name,
            image: "",
          ),
          series: create.readerSeries,
          chapterId: seriesId,
          initRank: initRank,
          loadChapter: (seriesId) => _loadChapter(create, seriesId),
        ),
      ),
    );
  }

  Future<ChapterResponse> _loadChapter(
    DownloadCreate create,
    int seriesId,
  ) async {
    if (!create.containsChapterId(seriesId)) {
      throw StateError('download chapter is unavailable');
    }
    final images = ReaderPageRepository.orderOfflineImages(
      await methods.dlImageByChapterId(seriesId),
    );
    final chapter = create.chapterById(seriesId);
    if (chapter == null) {
      throw StateError('download chapter metadata is missing');
    }
    return ChapterResponse(
      id: seriesId,
      series: create.readerSeries,
      tags: create.album.tags.join(" / "),
      name: chapter.name,
      images: images.map((e) => e.name).toList(growable: false),
      seriesId: create.album.id,
      isFavorite: false,
      liked: false,
      offlineImages: images,
    );
  }
}

class _DownloadHero extends StatelessWidget {
  final DownloadAlbum album;

  const _DownloadHero({required this.album});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 19;
    final coverWidth = compact ? 82.0 : 96.0;
    final status = _DownloadStatus.of(context, album);
    final progress = album.downloadProgress ?? 0;
    final percent = (progress * 100).round();

    return Container(
      key: const ValueKey('download-detail-hero'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            status.color.withValues(alpha: .11),
            scheme.surfaceContainerLow,
          ],
        ),
        border: Border.all(
          color: status.color.withValues(alpha: .18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: JM3x4Cover(
                comicId: album.id,
                width: coverWidth,
                height: coverWidth * 4 / 3,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StatusPill(status: status),
                    const Spacer(),
                    Text(
                      '$percent%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: status.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  album.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                if (album.authorLabel.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    album.authorLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 13),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: status.color,
                    backgroundColor: status.color.withValues(alpha: .12),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.tr(
                    '${album.dledImageCount} / ${album.imageCount} 张图片',
                    en: '${album.dledImageCount} / ${album.imageCount} images',
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
        ],
      ),
    );
  }
}

class _DownloadStatus {
  final String label;
  final IconData icon;
  final Color color;

  const _DownloadStatus(this.label, this.icon, this.color);

  factory _DownloadStatus.of(BuildContext context, DownloadAlbum album) {
    if (album.isDownloaded) {
      return _DownloadStatus(
        context.l10n.tr('已下载', en: 'Downloaded'),
        Icons.check_circle_rounded,
        Colors.green,
      );
    }
    if (album.isFailed) {
      return _DownloadStatus(
        context.l10n.tr('下载失败', en: 'Failed'),
        Icons.error_rounded,
        Theme.of(context).colorScheme.error,
      );
    }
    if (album.isDeleting) {
      return _DownloadStatus(
        context.l10n.tr('删除中', en: 'Deleting'),
        Icons.delete_sweep_rounded,
        Colors.orange,
      );
    }
    return _DownloadStatus(
      context.l10n.tr('下载中', en: 'Downloading'),
      Icons.downloading_rounded,
      Colors.blue,
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _DownloadStatus status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: status.color),
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

class _ReadEntryButton extends StatelessWidget {
  final String label;
  final String? detail;
  final IconData icon;
  final VoidCallback? onPressed;

  const _ReadEntryButton({
    required this.label,
    required this.icon,
    this.detail,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null;
    final foreground = enabled ? scheme.onPrimaryContainer : scheme.onSurface;
    final background = enabled
        ? [scheme.primaryContainer, scheme.tertiaryContainer]
        : [scheme.surfaceContainerHigh, scheme.surfaceContainerHighest];
    return Material(
      key: const ValueKey('download-detail-read'),
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: enabled
              ? scheme.primary.withValues(alpha: .2)
              : scheme.outlineVariant.withValues(alpha: .4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: background,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (enabled ? scheme.primary : scheme.onSurface)
                        .withValues(alpha: enabled ? .14 : .07),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 24, color: foreground),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (detail != null && detail!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: foreground.withValues(alpha: .72),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: foreground,
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

class _DownloadTags extends StatelessWidget {
  final List<String> tags;

  const _DownloadTags({required this.tags});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.tr('标签', en: 'Tags'),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final tag in tags)
              ActionChip(
                label: Text(tag),
                visualDensity: VisualDensity.compact,
                side: BorderSide(
                  color: scheme.primary.withValues(alpha: .16),
                ),
                backgroundColor: scheme.primaryContainer.withValues(alpha: .45),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ComicSearchScreen(initKeywords: tag),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _DownloadDescription extends StatelessWidget {
  final String description;

  const _DownloadDescription({required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.tr('简介', en: 'Description'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          SelectableText(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.55,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterHeader extends StatelessWidget {
  final int count;

  const _ChapterHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.tr('章节目录', en: 'Chapters'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            context.l10n.tr('$count 话', en: '$count chapters'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final DownloadCreateChapter chapter;
  final VoidCallback onTap;

  const _ChapterTile({
    required this.chapter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = chapter.name.trim().isEmpty
        ? context.l10n.tr('第 ${chapter.sort} 话', en: 'Chapter ${chapter.sort}')
        : chapter.name;
    return Material(
      key: ValueKey('download-detail-chapter-${chapter.id}'),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Text(
                  chapter.sort,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      context.l10n.tr('离线阅读', en: 'Read offline'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadStatusMessage extends StatelessWidget {
  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  const _DownloadStatusMessage.loading()
      : message = '',
        loading = true,
        onRetry = null;

  const _DownloadStatusMessage.error({required this.onRetry})
      : message = '下载任务读取失败',
        loading = false;

  const _DownloadStatusMessage.emptyChapters()
      : message = '暂无可阅读章节，下载任务可能尚未同步完成',
        loading = false,
        onRetry = null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: loading
          ? const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.tr(
                    message,
                    en: message == '下载任务读取失败'
                        ? 'Could not load the download task'
                        : 'No readable chapters are available yet',
                  ),
                  textAlign: TextAlign.center,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onRetry,
                    child: Text(context.l10n.tr('重试', en: 'Retry')),
                  ),
                ],
              ],
            ),
    );
  }
}
