import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/comic_info_screen.dart';

import 'images.dart';

class WeekComicFeed extends StatefulWidget {
  final String categoryId;
  final String typeId;

  const WeekComicFeed({
    super.key,
    required this.categoryId,
    required this.typeId,
  });

  @override
  State<WeekComicFeed> createState() => _WeekComicFeedState();
}

class _WeekComicFeedState extends State<WeekComicFeed> {
  final ScrollController _controller = ScrollController();
  final List<ComicSimple> _items = [];

  int _requestToken = 0;
  int _nextPage = 1;
  int _total = 0;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _reachedEnd = false;
  Object? _initialError;
  Object? _moreError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    unawaited(_reset());
  }

  @override
  void didUpdateWidget(covariant WeekComicFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId ||
        oldWidget.typeId != widget.typeId) {
      unawaited(_reset());
    }
  }

  @override
  void dispose() {
    _requestToken++;
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_controller.position.extentAfter < 420) {
      unawaited(_loadMore());
    }
  }

  Future<void> _reset() async {
    final token = ++_requestToken;
    setState(() {
      _items.clear();
      _nextPage = 1;
      _total = 0;
      _initialLoading = true;
      _loadingMore = false;
      _reachedEnd = false;
      _initialError = null;
      _moreError = null;
    });
    await _loadPage(1, token, initial: true);
  }

  Future<void> _loadMore() async {
    if (_initialLoading || _loadingMore || _reachedEnd) return;
    await _loadPage(_nextPage, _requestToken, initial: false);
  }

  Future<void> _loadPage(
    int page,
    int token, {
    required bool initial,
  }) async {
    if (!initial) {
      setState(() {
        _loadingMore = true;
        _moreError = null;
      });
    }
    try {
      final response =
          await methods.weekFilter(widget.categoryId, widget.typeId, page);
      if (!mounted || token != _requestToken) return;
      final seen = _items.map((comic) => comic.id).toSet();
      final incoming =
          response.list.where((comic) => seen.add(comic.id)).toList();
      setState(() {
        _items.addAll(incoming);
        _total = response.total;
        _nextPage = page + 1;
        _initialLoading = false;
        _loadingMore = false;
        _reachedEnd = incoming.isEmpty ||
            response.list.isEmpty ||
            (_total > 0 && _items.length >= _total);
        _initialError = null;
        _moreError = null;
      });
      _scheduleViewportCheck();
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _initialLoading = false;
        _loadingMore = false;
        if (initial) {
          _initialError = error;
        } else {
          _moreError = error;
        }
      });
    }
  }

  void _scheduleViewportCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      if (_controller.position.extentAfter < 240) {
        unawaited(_loadMore());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading && _items.isEmpty) {
      return Center(
        key: const ValueKey('week-feed-loading-initial'),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    if (_initialError != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 30),
            const SizedBox(height: 10),
            Text(context.l10n.tr('榜单加载失败', en: 'Could not load ranking')),
            TextButton.icon(
              key: const ValueKey('week-feed-retry'),
              onPressed: _reset,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.l10n.tr('重试', en: 'Retry')),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(context.l10n.noContentAvailable),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 12.0;
        const spacing = 10.0;
        final contentWidth = constraints.maxWidth - horizontalPadding * 2;
        final itemWidth = (contentWidth - spacing * 2) / 3;
        final itemHeight = itemWidth * 4 / 3 + 56;
        return RefreshIndicator(
          onRefresh: _reset,
          child: CustomScrollView(
            key: const ValueKey('week-comic-feed'),
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 15,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.tr('本期榜单', en: 'This issue'),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const Spacer(),
                      Text(
                        context.l10n.tr(
                          '$_total 部',
                          en: '$_total comics',
                        ),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: horizontalPadding),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _WeekComicCard(
                      comic: _items[index],
                      rank: index + 1,
                    ),
                    childCount: _items.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    mainAxisExtent: itemHeight,
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _footer(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _footer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loadingMore) {
      return const SizedBox(
        key: ValueKey('week-feed-loading-more'),
        height: 54,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_moreError != null) {
      return SizedBox(
        height: 54,
        child: Center(
          child: TextButton.icon(
            key: const ValueKey('week-feed-load-more-retry'),
            onPressed: _loadMore,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(context.l10n.tr('加载失败，点击重试', en: 'Retry loading')),
          ),
        ),
      );
    }
    if (_reachedEnd) {
      return SizedBox(
        key: const ValueKey('week-feed-end'),
        height: 46,
        child: Center(
          child: Text(
            context.l10n.tr('已经到底了', en: 'End of list'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    return const SizedBox(height: 46);
  }
}

class _WeekComicCard extends StatelessWidget {
  final ComicSimple comic;
  final int rank;

  const _WeekComicCard({
    required this.comic,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = comic.categorySub.title?.trim() ?? '';
    return RepaintBoundary(
      child: GestureDetector(
        key: ValueKey('week-comic-card-${comic.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ComicInfoScreen(comic.id, comic),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Material(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    JM3x4Cover(comicId: comic.id),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x52000000)],
                        ),
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Positioned(
                        top: 7,
                        left: 7,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 86),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .52),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 7,
                      bottom: 6,
                      child: Text(
                        rank.toString().padLeft(2, '0'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          shadows: const [
                            Shadow(color: Colors.black87, blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: Text(
                comic.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            SizedBox(
              height: 18,
              child: Text(
                comic.author.trim().isEmpty
                    ? context.l10n.tr('未知作者', en: 'Unknown author')
                    : comic.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
