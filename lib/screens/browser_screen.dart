import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/categories_sort.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/category_comics_screen.dart';
import 'package:jmcomic3/screens/comic_info_screen.dart';
import 'package:jmcomic3/screens/components/browser_bottom_sheet.dart';
import 'package:jmcomic3/screens/components/comic_floating_search_bar.dart'
    show blockStore;
import 'package:jmcomic3/screens/components/compose_ui.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';
import 'package:jmcomic3/screens/components/content_error.dart';
import 'package:jmcomic3/screens/components/content_loading.dart';
import 'package:jmcomic3/screens/components/images.dart';
import 'package:jmcomic3/screens/week_screen.dart';

class BrowserScreenWrapper extends StatefulWidget {
  final VoidCallback onSearchRequested;

  const BrowserScreenWrapper({Key? key, required this.onSearchRequested})
      : super(key: key);

  @override
  State<BrowserScreenWrapper> createState() => _BrowserScreenWrapperState();
}

class _BrowserScreenWrapperState extends State<BrowserScreenWrapper> {
  @override
  void initState() {
    loginEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    loginEvent.unsubscribe(_setState);
    super.dispose();
  }

  void _setState(_) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    switch (loginStatus) {
      case LoginStatus.loginSuccess:
      case LoginStatus.guest:
        return BrowserScreen(onSearchRequested: widget.onSearchRequested);
      case LoginStatus.loginField:
        return ContentError(
          error: context.l10n.pleaseLogin,
          stackTrace: StackTrace.current,
          onRefresh: () async {},
        );
      case LoginStatus.logging:
        return ContentLoading(label: context.l10n.loggingIn);
      case LoginStatus.notSet:
        return ContentError(
          error: context.l10n.pleaseLogin,
          stackTrace: StackTrace.current,
          onRefresh: () async {},
        );
    }
  }
}

class BrowserScreen extends StatefulWidget {
  final VoidCallback onSearchRequested;

  const BrowserScreen({Key? key, required this.onSearchRequested})
      : super(key: key);

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<CategoriesResponse> _future;
  late Key _feedKey = UniqueKey();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _loadCategories();
    categoriesSortEvent.subscribe(_resort);
  }

  @override
  void dispose() {
    categoriesSortEvent.unsubscribe(_resort);
    super.dispose();
  }

  Future<CategoriesResponse> _loadCategories() async {
    final response = await methods.categories();
    blockStore = response.blocks;
    sortCategories(response.categories);
    return response;
  }

  void _resort(_) {
    if (!mounted) return;
    setState(() {
      _future = _loadCategories();
      _feedKey = UniqueKey();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadCategories();
      _feedKey = UniqueKey();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      key: const ValueKey('compose-browse-page'),
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context)
                  .colorScheme
                  .surfaceContainerLow
                  .withValues(alpha: .55),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: ContentBuilder<CategoriesResponse>(
                  future: _future,
                  onRefresh: _refresh,
                  successBuilder: (context, snapshot) {
                    final categories = snapshot.requireData.categories;
                    if (categories.isEmpty) {
                      return Center(
                        child: Text(
                          context.l10n.tr(
                            '暂无可用分类',
                            en: 'No categories available',
                          ),
                        ),
                      );
                    }
                    return _HomeFeed(
                      key: _feedKey,
                      categories: categories,
                      onRefresh: _refresh,
                      onSearchRequested: widget.onSearchRequested,
                    );
                  },
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 82,
              child: _WeeklyFloatingTab(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WeekScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeFeed extends StatelessWidget {
  final List<Categories> categories;
  final Future<void> Function() onRefresh;
  final VoidCallback onSearchRequested;

  const _HomeFeed({
    required this.categories,
    required this.onRefresh,
    required this.onSearchRequested,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey('home-feed'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 126),
        children: [
          ComposeReveal(
            child: _HomeTopBar(onSearchRequested: onSearchRequested),
          ),
          ComposeReveal(
            delay: const Duration(milliseconds: 30),
            child: _HeroCarouselSection(
              key: ValueKey('home-hero:${categories.first.slug}'),
              category: categories.first,
            ),
          ),
          for (var index = 0; index < categories.length; index++)
            _HomeComicSection(
              key: ValueKey('home-section:${categories[index].slug}'),
              category: categories[index],
              title: categories[index].name.trim().isEmpty
                  ? categories[index].slug
                  : categories[index].name,
              revealDelay: Duration(milliseconds: 30 * math.min(index, 4)),
            ),
        ],
      ),
    );
  }
}

class _HomeTopBar extends StatelessWidget {
  final VoidCallback onSearchRequested;

  const _HomeTopBar({required this.onSearchRequested});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 840;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 10 : 16, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact ? double.infinity : 430,
                ),
                child: _CompactSearchEntry(onTap: onSearchRequested),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const BrowserBottomSheetAction(),
        ],
      ),
    );
  }
}

class _CompactSearchEntry extends StatelessWidget {
  final VoidCallback onTap;

  const _CompactSearchEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('home-search-entry'),
        onTap: onTap,
        child: Ink(
          height: 42,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: .84),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .52),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .045),
                blurRadius: 20,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 19, color: scheme.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    context.l10n.tr(
                      '搜索漫画、作者或关键词',
                      en: 'Search comics, authors or keywords',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
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

class _HeroCarouselSection extends StatefulWidget {
  final Categories category;

  const _HeroCarouselSection({required this.category, super.key});

  @override
  State<_HeroCarouselSection> createState() => _HeroCarouselSectionState();
}

class _HeroCarouselSectionState extends State<_HeroCarouselSection> {
  late final Future<ComicsResponse> _future = _load();

  Future<ComicsResponse> _load() {
    return methods.comics(widget.category.slug, sortByNew, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 21),
      child: FutureBuilder<ComicsResponse>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const _HeroSkeleton();
          }
          final comics = snapshot.requireData.content.take(5).toList();
          if (comics.isEmpty) {
            return const SizedBox.shrink();
          }
          return _HomeCarousel(comics: comics);
        },
      ),
    );
  }
}

class _HomeCarousel extends StatefulWidget {
  final List<ComicSimple> comics;

  const _HomeCarousel({required this.comics});

  @override
  State<_HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<_HomeCarousel> {
  late final PageController _controller = PageController();
  Timer? _timer;
  int _current = 0;
  bool _timerStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timerStarted) return;
    _timerStarted = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startTimer());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    if (!mounted || widget.comics.length < 2) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_controller.hasClients) return;
      final next = (_current + 1) % widget.comics.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).width >= 840 ? 250.0 : 188.0;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final showSupportingText = textScale <= 1.6;
    final titleStyle = showSupportingText
        ? Theme.of(context).textTheme.headlineSmall
        : Theme.of(context).textTheme.titleLarge;
    return RepaintBoundary(
      child: SizedBox(
        key: const ValueKey('home-carousel'),
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.comics.length,
                onPageChanged: (index) {
                  setState(() => _current = index);
                },
                itemBuilder: (context, index) {
                  final comic = widget.comics[index];
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openComic(context, comic),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: ClipRect(
                            child: JM3x4Cover(
                              comicId: comic.id,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0xC20E1B20),
                                Color(0x4D0E1B20),
                                Color(0x0D0E1B20),
                              ],
                            ),
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Color(0x550E1B20),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: height * .46,
                          bottom: 23,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showSupportingText) ...[
                                _HeroBadge(
                                  label: index == 0
                                      ? context.l10n.tr(
                                          '本周精选',
                                          en: 'Weekly pick',
                                        )
                                      : comic.category.title ??
                                          context.l10n.tr(
                                            '热门推荐',
                                            en: 'Featured',
                                          ),
                                ),
                                const SizedBox(height: 9),
                              ],
                              Text(
                                comic.name,
                                maxLines: showSupportingText ? 2 : 3,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  height: 1.12,
                                  letterSpacing: -.4,
                                ),
                              ),
                              if (showSupportingText) ...[
                                const SizedBox(height: 6),
                                Text(
                                  comic.author.trim().isEmpty
                                      ? context.l10n.tr(
                                          '编辑推荐 · 持续更新',
                                          en: 'Editor pick · Updating',
                                        )
                                      : comic.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color:
                                            Colors.white.withValues(alpha: .76),
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < widget.comics.length; index++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: index == _current ? 18 : 6,
                        height: 6,
                        margin: const EdgeInsets.only(left: 5),
                        decoration: BoxDecoration(
                          color: index == _current
                              ? Colors.white
                              : Colors.white.withValues(alpha: .42),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  final String label;

  const _HeroBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: .28)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: .5,
            ),
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.sizeOf(context).width >= 840 ? 250 : 188,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: .58),
            scheme.secondaryContainer.withValues(alpha: .42),
          ],
        ),
        borderRadius: BorderRadius.circular(25),
      ),
    );
  }
}

class _HomeComicSection extends StatefulWidget {
  final Categories category;
  final String title;
  final Duration revealDelay;

  const _HomeComicSection({
    required this.category,
    required this.title,
    required this.revealDelay,
    super.key,
  });

  @override
  State<_HomeComicSection> createState() => _HomeComicSectionState();
}

class _HomeComicSectionState extends State<_HomeComicSection> {
  late Future<ComicsResponse> _future = _load();

  Future<ComicsResponse> _load() {
    return methods.comics(widget.category.slug, sortByNew, 1);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final railHeight = textScale >= 1.8
        ? 250.0
        : textScale >= 1.3
            ? 226.0
            : 208.0;
    return ComposeReveal(
      delay: widget.revealDelay,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: widget.title,
              onMore: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CategoryComicsScreen(
                      category: widget.category,
                    ),
                  ),
                );
              },
            ),
            SizedBox(
              height: railHeight,
              child: FutureBuilder<ComicsResponse>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh, size: 17),
                        label: Text(
                          context.l10n.tr('重新加载', en: 'Retry'),
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const _RailSkeleton();
                  }
                  final comics = snapshot.requireData.content;
                  if (comics.isEmpty) {
                    return Center(
                      child: Text(
                        context.l10n.noContentAvailable,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }
                  return ListView.separated(
                    key: ValueKey('home-rail:${widget.category.slug}'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const BouncingScrollPhysics(),
                    itemCount: comics.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      return _HomeComicCard(comic: comics[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onMore;

  const _SectionHeader({required this.title, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 17,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [scheme.primary, scheme.primary.withValues(alpha: .35)],
              ),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.2,
                  ),
            ),
          ),
          TextButton(
            onPressed: onMore,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: scheme.onSurfaceVariant,
            ),
            child: Text(
              context.l10n.tr('查看更多', en: 'More'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _HomeComicCard extends StatelessWidget {
  final ComicSimple comic;

  const _HomeComicCard({required this.comic});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: SizedBox(
        width: 112,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openComic(context, comic),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 150,
                child: Material(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(15),
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
                            colors: [Colors.transparent, Color(0x38000000)],
                          ),
                        ),
                      ),
                      if ((comic.categorySub.title ?? '').isNotEmpty)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 90),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .48),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              comic.categorySub.title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontSize: 9,
                                  ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                comic.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                comic.author.trim().isEmpty
                    ? context.l10n.tr('未知作者', en: 'Unknown author')
                    : comic.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (_, __) {
        return SizedBox(
          width: 112,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .68),
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 10,
                width: 84,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WeeklyFloatingTab extends StatelessWidget {
  final VoidCallback onTap;

  const _WeeklyFloatingTab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
        bottomLeft: Radius.circular(16),
        bottomRight: Radius.circular(5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('weekly-floating-tab'),
        onTap: onTap,
        child: Ink(
          height: 38,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: .94),
            border: Border.all(
              color: scheme.primary.withValues(alpha: .16),
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  size: 17,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 7),
                Text(
                  context.l10n.weekMustSee,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
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

void _openComic(BuildContext context, ComicBasic comic) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ComicInfoScreen(comic.id, comic),
    ),
  );
}
