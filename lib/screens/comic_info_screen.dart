import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/local_bookshelf.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/basic/navigator.dart';
import 'package:jmcomic3/configs/ignore_view_log.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'comic_download_screen.dart';
import 'comic_reader_screen.dart';
import 'comic_search_screen.dart';
import 'components/bookshelf_group_picker.dart';
import 'components/comic_comments_list.dart';
import 'components/comic_detail_chapters.dart';
import 'components/comic_detail_header.dart';
import 'components/comic_list.dart';
import 'components/right_click_pop.dart';

ComicBasic? effectiveComicInfoSimple(ComicBasic? simple, int comicId) {
  if (simple == null || simple.name.trim().isEmpty) return null;
  final normalized =
      simple.name.trim().toUpperCase().replaceAll(RegExp(r'[\s#]+'), '');
  // A local ID-only history entry must not hide the album's real metadata.
  if (normalized == comicId.toString() || normalized == 'JM$comicId') {
    return null;
  }
  return simple;
}

({int chapterId, int page, bool continuing}) comicDetailReadingTarget(
    AlbumResponse album, ViewLog? viewLog) {
  final canResume = viewLog != null &&
      viewLog.id == album.id &&
      viewLog.lastViewChapterId > 0 &&
      (album.series.isEmpty
          ? viewLog.lastViewChapterId == album.id
          : album.series
              .any((chapter) => chapter.id == viewLog.lastViewChapterId));
  if (canResume) {
    return (
      chapterId: viewLog.lastViewChapterId,
      page: viewLog.lastViewPage < 0 ? 0 : viewLog.lastViewPage,
      continuing: true,
    );
  }
  return (
    chapterId: album.initialReadableChapterId,
    page: 0,
    continuing: false
  );
}

class ComicInfoScreen extends StatefulWidget {
  final int comicId;
  final ComicBasic? simple;

  const ComicInfoScreen(this.comicId, this.simple, {super.key});

  @override
  State<ComicInfoScreen> createState() => _ComicInfoScreenState();
}

class _ComicInfoScreenState extends State<ComicInfoScreen> with RouteAware {
  static const _contentWidth = 800.0;
  bool _bookshelfLoading = true;
  bool _inBookshelf = false;
  Timer? _viewLogRefreshTimer;
  ModalRoute<void>? _route;
  late Future<AlbumResponse> _albumFuture = _loadAlbum();
  late Future<ViewLog?> _viewFuture = methods.findViewLog(widget.comicId);

  Future<AlbumResponse> _loadAlbum() async {
    final bookshelfFuture = loadLocalBookshelf();
    final album = await methods.album(
      widget.comicId,
      ignoreViewLog: currentIgnoreVewLog(),
    );
    unawaited(_syncBookshelf(bookshelfFuture, album.id));
    return album;
  }

  Future<void> _syncBookshelf(Future<void> future, int comicId) async {
    await future;
    if (!mounted || widget.comicId != comicId) return;
    setState(() {
      _inBookshelf = localBookshelfContains(comicId);
      _bookshelfLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    localBookshelfEvent.subscribe(_bookshelfChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      routeObserver.unsubscribe(this);
      _route = route;
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(covariant ComicInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comicId != widget.comicId) {
      _inBookshelf = false;
      _bookshelfLoading = true;
      _albumFuture = _loadAlbum();
      _viewFuture = methods.findViewLog(widget.comicId);
    }
  }

  @override
  void didPopNext() {
    _viewLogRefreshTimer?.cancel();
    _viewLogRefreshTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _viewFuture = methods.findViewLog(widget.comicId);
      });
    });
  }

  @override
  void dispose() {
    _viewLogRefreshTimer?.cancel();
    localBookshelfEvent.unsubscribe(_bookshelfChanged);
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  void _bookshelfChanged(_) {
    if (!mounted) return;
    final inShelf = localBookshelfContains(widget.comicId);
    if (_inBookshelf != inShelf) {
      setState(() => _inBookshelf = inShelf);
    }
  }

  Future<void> _refresh() async {
    final future = _loadAlbum();
    setState(() {
      _albumFuture = future;
      _viewFuture = methods.findViewLog(widget.comicId);
    });
    try {
      await future;
    } catch (_) {
      // The album FutureBuilder owns the retry state.
    }
  }

  void _search(String keyword) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ComicSearchScreen(initKeywords: keyword),
      ));

  void _download(AlbumResponse album) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ComicDownloadScreen(album)),
      );

  void _read(AlbumResponse album, int chapterId, int page) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ComicReaderScreen(
        comic: albumToSimple(album),
        series: album.series,
        chapterId: chapterId,
        initRank: page,
        loadChapter: methods.chapter,
      ),
    ));
  }

  Future<void> _changeBookshelf(AlbumResponse album) async {
    if (_bookshelfLoading) return;
    setState(() => _bookshelfLoading = true);
    try {
      final inShelf = await toggleLocalBookshelf(
        albumToSimple(album),
      );
      if (!mounted) return;
      setState(() {
        _inBookshelf = inShelf;
      });
      defaultToast(
        context,
        inShelf
            ? context.l10n.tr('已加入书架', en: 'Added to bookshelf')
            : context.l10n.tr('已从书架移除', en: 'Removed from bookshelf'),
      );
    } catch (error) {
      if (mounted) defaultToast(context, '$error');
    } finally {
      if (mounted) setState(() => _bookshelfLoading = false);
    }
  }

  Future<void> _changeBookshelfGroup(AlbumResponse album) async {
    if (_bookshelfLoading) return;
    setState(() => _bookshelfLoading = true);
    try {
      await loadLocalBookshelf();
      if (!mounted) return;
      String? currentGroup;
      for (final item in localBookshelfItems) {
        if (item.comic.id == album.id) {
          currentGroup = item.group;
          break;
        }
      }
      final choice = await showBookshelfGroupPicker(
        context,
        groups: localBookshelfGroupNames,
        selectedGroup: currentGroup,
        comicName: album.name,
      );
      if (!mounted || choice == null) return;

      var targetGroup = choice.group;
      if (choice.createNew) {
        final name = await showBookshelfGroupNameDialog(
          context,
          existingNames: localBookshelfGroupNames,
        );
        if (!mounted || name == null || name.trim().isEmpty) return;
        targetGroup = name.trim();
        await createLocalBookshelfGroup(targetGroup);
      }
      if (targetGroup == null) return;

      final wasInBookshelf = localBookshelfContains(album.id);
      if (wasInBookshelf) {
        final moved =
            await moveLocalBookshelfItem(album.id, targetGroup.trim());
        if (!moved) {
          throw StateError('Bookshelf comic not found');
        }
      } else {
        final added = await toggleLocalBookshelf(
          albumToSimple(album),
          group: targetGroup.trim(),
        );
        if (!added) {
          throw StateError('Could not add comic to bookshelf');
        }
      }
      if (!mounted) return;
      setState(() => _inBookshelf = true);
      defaultToast(
        context,
        context.l10n.tr(
          '已加入分组“$targetGroup”',
          en: 'Added to “$targetGroup”',
        ),
      );
    } catch (error) {
      if (mounted) defaultToast(context, '$error');
    } finally {
      if (mounted) setState(() => _bookshelfLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.brightness == Brightness.dark
        ? const Color(0xFF0D0D0F)
        : theme.colorScheme.surface;
    return rightClickPop(
      context: context,
      child: FutureBuilder<AlbumResponse>(
        future: _albumFuture,
        builder: (context, snapshot) {
          final album = snapshot.connectionState == ConnectionState.done &&
                  !snapshot.hasError
              ? snapshot.data
              : null;
          return Scaffold(
            backgroundColor: background,
            appBar: AppBar(
              backgroundColor: background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: _navButton(
                  Icons.chevron_left,
                  () => Navigator.maybePop(context),
                  context.l10n.tr('返回', en: 'Back')),
              actions: [
                if (album != null) ...[
                  _navButton(
                      Icons.file_download_outlined,
                      () => _download(album),
                      context.l10n.tr('下载', en: 'Download')),
                  _navButton(
                      _inBookshelf
                          ? Icons.bookmark_added_rounded
                          : Icons.bookmark_add_outlined,
                      _bookshelfLoading ? null : () => _changeBookshelf(album),
                      _inBookshelf
                          ? context.l10n.tr(
                              '已在书架 · 长按选择分组',
                              en: 'In bookshelf · Long-press to choose a group',
                            )
                          : context.l10n.tr(
                              '加入书架 · 长按选择分组',
                              en: 'Add to bookshelf · Long-press to choose a group',
                            ),
                      onLongPress: _bookshelfLoading
                          ? null
                          : () => _changeBookshelfGroup(album)),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            body: album != null
                ? _body(album)
                : _loadingOrError(snapshot.hasError),
            bottomNavigationBar:
                album != null ? _bottomBar(album, background) : null,
          );
        },
      ),
    );
  }

  Widget _navButton(
    IconData icon,
    VoidCallback? onPressed,
    String tooltip, {
    GestureLongPressCallback? onLongPress,
  }) {
    final button = IconButton(
      tooltip: onLongPress == null ? tooltip : null,
      onPressed: onPressed,
      icon: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .05),
        ),
        child: Padding(
            padding: const EdgeInsets.all(8), child: Icon(icon, size: 20)),
      ),
    );
    if (onLongPress == null) return button;
    return Semantics(
      label: tooltip,
      button: true,
      onLongPress: onLongPress,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress,
        child: button,
      ),
    );
  }

  Widget _loadingOrError(bool error) {
    return Center(
      child: error
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_outlined, size: 32),
              const SizedBox(height: 12),
              Text(context.l10n.tr('漫画详情加载失败', en: 'Could not load comic')),
              TextButton.icon(
                key: const ValueKey('comic-detail-retry'),
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.tr('重试', en: 'Retry')),
              ),
            ])
          : const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }

  Widget _body(AlbumResponse album) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        key: const ValueKey('comic-detail-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ComicDetailHeader(
                    key: ValueKey(album.id),
                    album: album,
                    simple:
                        effectiveComicInfoSimple(widget.simple, widget.comicId),
                    onSearch: _search,
                  ),
                  _ComicDetailDirectory(
                    key: ValueKey('comic-detail-directory-${album.id}'),
                    album: album,
                    viewFuture: _viewFuture,
                    onRead: (chapter, page) => _read(album, chapter, page),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(AlbumResponse album, Color background) {
    return Container(
      decoration: BoxDecoration(
          gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [background.withValues(alpha: 0), background, background],
        stops: const [0, .3, 1],
      )),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentWidth - 32),
              child: Row(children: [
                _action(
                    'comic-detail-download',
                    Icons.file_download_outlined,
                    context.l10n.tr('下载', en: 'Download'),
                    () => _download(album)),
                const SizedBox(width: 4),
                _action(
                    'comic-detail-favorite',
                    _bookshelfLoading
                        ? Icons.sync
                        : _inBookshelf
                            ? Icons.bookmark_added_rounded
                            : Icons.bookmark_add_outlined,
                    _inBookshelf
                        ? context.l10n.tr('已在书架', en: 'In bookshelf')
                        : context.l10n.tr('加入书架', en: 'Add to bookshelf'),
                    _bookshelfLoading ? null : () => _changeBookshelf(album),
                    onLongPress: _bookshelfLoading
                        ? null
                        : () => _changeBookshelfGroup(album)),
                const SizedBox(width: 12),
                Expanded(
                    child: FutureBuilder<ViewLog?>(
                  future: _viewFuture,
                  builder: (context, snapshot) {
                    final ready =
                        snapshot.connectionState == ConnectionState.done;
                    final target =
                        comicDetailReadingTarget(album, snapshot.data);
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: ready
                            ? const LinearGradient(
                                colors: [Color(0xFF19CADE), Color(0xFF347FF5)])
                            : null,
                      ),
                      child: FilledButton(
                        key: const ValueKey('comic-detail-read'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          shape: const StadiumBorder(),
                          textStyle: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                  fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        onPressed: ready
                            ? () => _read(album, target.chapterId, target.page)
                            : null,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                              !ready
                                  ? context.l10n.loading
                                  : target.continuing
                                      ? context.l10n
                                          .tr('继续阅读', en: 'Continue reading')
                                      : context.l10n
                                          .tr('开始阅读', en: 'Start reading'),
                              textAlign: TextAlign.center),
                          if (ready && target.continuing)
                            Text('P${target.page + 1}',
                                style: const TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w400)),
                        ]),
                      ),
                    );
                  },
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(
    String key,
    IconData icon,
    String label,
    VoidCallback? onTap, {
    GestureLongPressCallback? onLongPress,
  }) {
    final button = TextButton(
      key: ValueKey(key),
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 20),
        const SizedBox(height: 3),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w400)),
      ]),
    );
    return SizedBox(
      width: 54,
      child: onLongPress == null
          ? button
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: onLongPress,
              child: button,
            ),
    );
  }
}

class _ComicDetailDirectory extends StatefulWidget {
  final AlbumResponse album;
  final Future<ViewLog?> viewFuture;
  final void Function(int chapterId, int page) onRead;

  const _ComicDetailDirectory({
    super.key,
    required this.album,
    required this.viewFuture,
    required this.onRead,
  });

  @override
  State<_ComicDetailDirectory> createState() => _ComicDetailDirectoryState();
}

class _ComicDetailDirectoryState extends State<_ComicDetailDirectory> {
  int _tabIndex = 0;
  final Set<int> _visitedTabs = {0};

  @override
  void didUpdateWidget(covariant _ComicDetailDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.id != widget.album.id) {
      _tabIndex = 0;
      _visitedTabs
        ..clear()
        ..add(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: _tabs(context),
        ),
        Divider(
          key: const ValueKey('comic-detail-directory-divider'),
          height: 24,
          thickness: .8,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TickerMode(
                enabled: _tabIndex == 0,
                child: Offstage(
                  key: const ValueKey('comic-detail-panel-chapters'),
                  offstage: _tabIndex != 0,
                  child: RepaintBoundary(
                    child: ComicDetailChapters(
                      album: album,
                      viewFuture: widget.viewFuture,
                      onRead: widget.onRead,
                    ),
                  ),
                ),
              ),
              if (_visitedTabs.contains(1))
                TickerMode(
                  enabled: _tabIndex == 1,
                  child: Offstage(
                    key: const ValueKey('comic-detail-panel-comments'),
                    offstage: _tabIndex != 1,
                    child: RepaintBoundary(
                      child: ComicCommentsList(
                        mode: 'manhua',
                        aid: album.id,
                      ),
                    ),
                  ),
                ),
              if (_visitedTabs.contains(2))
                TickerMode(
                  enabled: _tabIndex == 2,
                  child: Offstage(
                    key: const ValueKey('comic-detail-panel-related'),
                    offstage: _tabIndex != 2,
                    child: RepaintBoundary(
                      child: album.relatedList.isEmpty
                          ? _emptyPanel(context)
                          : ComicList(
                              data: album.relatedList,
                              inScroll: true,
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabs(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labels = [
      '${context.l10n.tr('章节', en: 'Chapters')} ${widget.album.series.length}',
      '${context.l10n.tr('评论', en: 'Comments')} ${widget.album.commentTotal}',
      '${context.l10n.tr('推荐', en: 'Recommended')} '
          '${widget.album.relatedList.length}',
    ];
    final textScaler = MediaQuery.textScalerOf(context);
    final tabHeight =
        (textScaler.scale(13) * 1.35 + 24).clamp(48.0, 76.0).toDouble();

    return Material(
      color: scheme.onSurface.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widths = labels.map((label) {
            final painter = TextPainter(
              text: TextSpan(
                text: label,
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
              ),
              textScaler: textScaler,
              textDirection: Directionality.of(context),
            )..layout();
            final width = painter.width + 24;
            painter.dispose();
            return width;
          }).toList();
          final scrollable =
              widths.any((width) => width > constraints.maxWidth / 3);

          Widget tab(int index) {
            final selected = index == _tabIndex;
            return Semantics(
              selected: selected,
              button: true,
              child: InkWell(
                key: ValueKey('comic-detail-tab-$index'),
                onTap: () => setState(() {
                  _tabIndex = index;
                  _visitedTabs.add(index);
                }),
                child: SizedBox(
                  height: tabHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          labels[index],
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w500 : FontWeight.w400,
                            color: selected
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 2,
                          width: selected ? 32 : 0,
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF22CDE0)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          final row = SizedBox(
            height: tabHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < labels.length; index++)
                  scrollable
                      ? SizedBox(width: widths[index], child: tab(index))
                      : Expanded(child: tab(index)),
              ],
            ),
          );
          return scrollable
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: row,
                )
              : row;
        },
      ),
    );
  }

  Widget _emptyPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: .03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        context.l10n.tr('暂无推荐', en: 'No recommendations'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }
}
