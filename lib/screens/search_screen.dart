import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/categories_sort.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_floating_search_bar.dart';
import 'package:jmcomic3/screens/components/comic_pager.dart';
import 'package:jmcomic3/screens/components/compose_ui.dart';

import 'components/browser_bottom_sheet.dart';

class SearchScreen extends StatefulWidget {
  final bool active;
  final Future<String?> Function()? pickImageFile;

  const SearchScreen({
    this.active = true,
    this.pickImageFile,
    Key? key,
  }) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<SearchHistory> _histories = const [];
  List<Block> _blocks = const [];
  String _query = '';
  String? _resultLabel;
  SortBy _sortBy = sortByDefault;
  bool _loadingSuggestions = true;
  bool _suggestionsLoaded = false;
  bool _imageSearching = false;
  bool _historyExpanded = true;
  final Set<int> _expandedBlocks = {};
  Timer? _suggestionLoadTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    if (widget.active) {
      _scheduleSuggestions();
    }
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active && !_suggestionsLoaded) {
      setState(() {
        _loadingSuggestions = true;
      });
      _scheduleSuggestions();
    }
  }

  @override
  void dispose() {
    _suggestionLoadTimer?.cancel();
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleSuggestions() {
    _suggestionLoadTimer?.cancel();
    _suggestionLoadTimer = Timer(
      const Duration(milliseconds: 320),
      () {
        if (mounted) _loadSuggestions();
      },
    );
  }

  Future<void> _loadSuggestions() async {
    if (_suggestionsLoaded) return;
    try {
      final results = await Future.wait<Object>([
        methods.lastSearchHistories(20),
        methods.categories(),
      ]);
      final histories = results[0] as List<SearchHistory>;
      final categories = results[1] as CategoriesResponse;
      blockStore = categories.blocks;
      sortCategories(categories.categories);
      if (!mounted) return;
      setState(() {
        _histories = histories;
        _blocks = searchBlocks;
        _loadingSuggestions = false;
        _suggestionsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSuggestions = false;
      });
    }
  }

  Future<void> _refreshSearchHistory() async {
    try {
      final histories = await methods.lastSearchHistories(20);
      if (!mounted) return;
      setState(() {
        _histories = histories;
      });
    } catch (_) {
      // Keep the currently visible history when the refresh fails.
    }
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _submit([String? value, String? displayValue]) {
    final query = (value ?? _controller.text).trim();
    if (query.isEmpty) return;
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _focusNode.unfocus();
    setState(() {
      _query = query;
      _resultLabel = displayValue?.trim();
    });
  }

  void _clearQuery() {
    _controller.clear();
    setState(() {
      _query = '';
      _resultLabel = null;
    });
    _focusNode.requestFocus();
  }

  Future<String?> _pickImageSearchFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }

  Future<void> _startImageSearch() async {
    if (_imageSearching) return;
    String? path;
    try {
      path = await (widget.pickImageFile ?? _pickImageSearchFile)();
    } catch (_) {
      if (mounted) {
        defaultToast(
          context,
          context.l10n.tr('无法选择图片', en: 'Could not select an image'),
        );
      }
      return;
    }
    if (path == null || path.trim().isEmpty || !mounted) return;

    setState(() => _imageSearching = true);
    try {
      final response = await methods.imageSearch(path);
      if (!mounted) return;
      final candidates = response.hits
          .where((hit) => hit.searchQuery.isNotEmpty)
          .toList(growable: false);
      setState(() => _imageSearching = false);
      if (candidates.isEmpty) {
        defaultToast(
          context,
          context.l10n.tr(
            '没有识别到可搜索的漫画，请换一张更清晰的图片',
            en: 'No searchable comic was found. Try a clearer image.',
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<ImageSearchHit>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ImageSearchResultsSheet(candidates),
      );
      if (selected == null || !mounted) return;
      _submit(selected.searchQuery, selected.displayTitle);
    } catch (error) {
      if (mounted) {
        setState(() => _imageSearching = false);
        defaultToast(context, _imageSearchErrorMessage(error));
      }
    }
  }

  String _imageSearchErrorMessage(Object error) {
    final text = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
    final lower = text.toLowerCase();
    if (text.contains('413')) {
      return context.l10n.tr(
        '图片文件太大，请换一张较小的图片',
        en: 'The image is too large. Choose a smaller image.',
      );
    }
    if (text.contains('415')) {
      return context.l10n.tr(
        '不支持这种图片格式，请使用 JPG、PNG 或 WebP',
        en: 'Unsupported image format. Use JPG, PNG, or WebP.',
      );
    }
    if (text.contains('429')) {
      return context.l10n.tr(
        '识图服务请求过于频繁，请稍后重试',
        en: 'Too many image searches. Try again shortly.',
      );
    }
    if (lower.contains('larger than 24 mb')) {
      return context.l10n.tr(
        '图片文件太大，请换一张不超过 24 MB 的图片',
        en: 'The image is too large. Choose one under 24 MB.',
      );
    }
    if (lower.contains('unsupported image')) {
      return context.l10n.tr(
        '不支持这种图片格式，请使用 JPG、PNG、WebP 或 GIF',
        en: 'Unsupported image format. Use JPG, PNG, WebP, or GIF.',
      );
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return context.l10n.tr(
        '识图请求超时，请检查网络后重试',
        en: 'Image search timed out. Check your network and retry.',
      );
    }
    return context.l10n.tr(
      '以图搜漫失败，请检查网络或稍后重试',
      en: 'Image search failed. Check your network or try again later.',
    );
  }

  void _handleBack() {
    if (_query.isNotEmpty) {
      unawaited(_refreshSearchHistory());
      _clearQuery();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final showingResults = _query.isNotEmpty;
    return PopScope(
      canPop: !showingResults,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _query.isNotEmpty) {
          _clearQuery();
        }
      },
      child: Scaffold(
        key: const ValueKey('compose-search-page'),
        backgroundColor: scheme.surface,
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 12, 6),
                    child: Row(
                      children: [
                        if (showingResults ||
                            Navigator.of(context).canPop()) ...[
                          IconButton.filledTonal(
                            tooltip: MaterialLocalizations.of(context)
                                .backButtonTooltip,
                            onPressed: _handleBack,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                showingResults
                                    ? context.l10n.tr(
                                        '搜索结果',
                                        en: 'Search results',
                                      )
                                    : context.l10n.navSearch,
                                style: (showingResults
                                        ? Theme.of(context).textTheme.titleLarge
                                        : Theme.of(context)
                                            .textTheme
                                            .headlineSmall)
                                    ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.4,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                showingResults
                                    ? _resultLabel == null
                                        ? '“$_query”'
                                        : context.l10n.tr(
                                            '以图匹配：$_resultLabel',
                                            en: 'Image match: $_resultLabel',
                                          )
                                    : context.l10n.tr(
                                        '按标题、作者或标签发现漫画',
                                        en: 'Find comics by title, author or tag',
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        if (showingResults)
                          IconButton.filledTonal(
                            tooltip:
                                '${context.l10n.chooseSort}: ${sortByName(context, _sortBy)}',
                            onPressed: _chooseSort,
                            icon: const Icon(Icons.sort_rounded),
                          ),
                        const BrowserBottomSheetAction(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: _buildSearchField(context),
                  ),
                  Expanded(
                    child: ComposePageSwitcher(
                      child: _query.isEmpty
                          ? _buildLanding(context)
                          : _buildResults(context),
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

  Widget _buildSearchField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _focusNode.hasFocus
              ? scheme.primary.withValues(alpha: .72)
              : scheme.outlineVariant.withValues(alpha: .58),
        ),
        boxShadow: _focusNode.hasFocus
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: .12),
                  blurRadius: 22,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: TextField(
        key: const ValueKey('compose-search-field'),
        controller: _controller,
        focusNode: _focusNode,
        textInputAction: TextInputAction.search,
        onSubmitted: _submit,
        decoration: InputDecoration(
          hintText: context.l10n.tr(
            '搜索漫画、作者或关键词',
            en: 'Search comics, authors or keywords',
          ),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('search-image-search'),
                  tooltip: context.l10n.tr('以图搜漫', en: 'Search by image'),
                  onPressed: _imageSearching ? null : _startImageSearch,
                  icon: _imageSearching
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image_search_rounded),
                ),
                if (value.text.isNotEmpty)
                  IconButton(
                    tooltip: context.l10n.tr('清除', en: 'Clear'),
                    onPressed: _clearQuery,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildLanding(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loadingSuggestions && widget.active) {
      return ListView(
        key: const ValueKey('search-landing'),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 120),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          ),
        ],
      );
    }
    if (!_suggestionsLoaded) {
      return const SizedBox.shrink();
    }
    final empty = _histories.isEmpty && _blocks.isEmpty;
    return ListView(
      key: const ValueKey('search-landing'),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 120),
      children: [
        if (_imageSearching) ...[
          const _ImageSearchStatusCard(),
          const SizedBox(height: 12),
        ],
        if (_histories.isNotEmpty) ...[
          _buildHistoryCard(context),
          const SizedBox(height: 12),
        ],
        for (var index = 0; index < _blocks.length; index++) ...[
          _buildTagBlock(context, index),
          const SizedBox(height: 12),
        ],
        if (empty)
          ComposeSurface(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 42),
            child: Column(
              children: [
                Icon(
                  Icons.manage_search_rounded,
                  size: 48,
                  color: scheme.primary,
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.tr(
                    '输入关键词开始搜索',
                    en: 'Enter a keyword to start searching',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ComposeSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.tr('最近搜索', en: 'Recent searches'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: const ValueKey('search-history-toggle'),
                tooltip: _historyExpanded
                    ? context.l10n.tr(
                        '收起最近搜索',
                        en: 'Collapse recent searches',
                      )
                    : context.l10n.tr(
                        '展开最近搜索',
                        en: 'Expand recent searches',
                      ),
                onPressed: () {
                  setState(() => _historyExpanded = !_historyExpanded);
                },
                icon: AnimatedRotation(
                  turns: _historyExpanded ? .5 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: const Icon(Icons.expand_more_rounded),
                ),
              ),
              IconButton(
                tooltip: context.l10n.tr(
                  '清除所有历史记录',
                  en: 'Clear all search history',
                ),
                onPressed: _clearSearchHistory,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _historyExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var index = 0; index < _histories.length; index++)
                          _SuggestionPill(
                            label: _histories[index].searchQuery,
                            icon: Icons.north_west_rounded,
                            onTap: () => _submit(_histories[index].searchQuery),
                            onLongPress: () =>
                                _removeSearchHistory(_histories[index]),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildTagBlock(BuildContext context, int index) {
    final scheme = Theme.of(context).colorScheme;
    final block = _blocks[index];
    final expanded = _expandedBlocks.contains(index);
    const collapsedCount = 12;
    final values = expanded
        ? block.content
        : block.content.take(collapsedCount).toList(growable: false);
    return ComposeSurface(
      key: ValueKey('search-tag-block-$index'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  block.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in values)
                _SuggestionPill(
                  label: value,
                  onTap: () => _submit(value),
                ),
            ],
          ),
          if (block.content.length > collapsedCount)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('search-tag-expand-$index'),
                onPressed: () {
                  setState(() {
                    if (expanded) {
                      _expandedBlocks.remove(index);
                    } else {
                      _expandedBlocks.add(index);
                    }
                  });
                },
                icon: Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  expanded
                      ? context.l10n.tr('收起', en: 'Show less')
                      : context.l10n.tr(
                          '显示全部 ${block.content.length} 个标签',
                          en: 'Show all ${block.content.length} tags',
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    return ComicPager(
      key: ValueKey('search-results:$_query:$_sortBy'),
      denseGrid: true,
      onPage: (page) async {
        final response = await methods.comicSearch(_query, _sortBy, page);
        if (page == 1) {
          unawaited(_refreshSearchHistory());
        }
        return InnerComicPage(
          total: response.total,
          list: response.content,
          redirectAid: response.redirectAid,
        );
      },
    );
  }

  Future<void> _chooseSort() async {
    final value = await chooseSortBy(context);
    if (!mounted || value == null) return;
    setState(() {
      _sortBy = value;
    });
  }

  Future<void> _clearSearchHistory() async {
    final choice = await chooseListDialog(
      context,
      values: [context.l10n.yes, context.l10n.no],
      title: context.l10n.tr(
        '清除所有历史记录?',
        en: 'Clear all search history?',
      ),
    );
    if (choice != context.l10n.yes) return;
    await methods.clearAllSearchLog();
    if (!mounted) return;
    setState(() {
      _histories = const [];
    });
  }

  Future<void> _removeSearchHistory(SearchHistory history) async {
    final choice = await chooseListDialog(
      context,
      values: [context.l10n.yes, context.l10n.no],
      title: context.l10n.tr(
        '清除历史记录“${history.searchQuery}”?',
        en: 'Clear history “${history.searchQuery}”?',
      ),
    );
    if (choice != context.l10n.yes) return;
    await methods.clearASearchLog(history.searchQuery);
    if (!mounted) return;
    setState(() {
      _histories = _histories
          .where((item) => item.searchQuery != history.searchQuery)
          .toList(growable: false);
    });
  }
}

class _ImageSearchStatusCard extends StatelessWidget {
  const _ImageSearchStatusCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ComposeSurface(
      key: const ValueKey('image-search-progress'),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr('正在以图搜漫', en: 'Searching by image'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.l10n.tr(
                    '图片将发送至 soutubot.moe 进行识别',
                    en: 'The image is sent to soutubot.moe for recognition',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

class _ImageSearchResultsSheet extends StatelessWidget {
  final List<ImageSearchHit> hits;

  const _ImageSearchResultsSheet(this.hits);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleHits = hits.take(12).toList(growable: false);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      child: Material(
        key: const ValueKey('image-search-results'),
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.image_search_rounded,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.tr(
                            '识别到 ${visibleHits.length} 个候选',
                            en: '${visibleHits.length} matches found',
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.tr(
                            '请选择最符合的漫画结果',
                            en: 'Choose the best matching comic',
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                itemCount: visibleHits.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final hit = visibleHits[index];
                  final isJm = hit.source.toLowerCase() == 'jmcomic';
                  final details = <String>[
                    hit.sourceLabel,
                    if (_imageLanguageLabel(hit.language).isNotEmpty)
                      _imageLanguageLabel(hit.language),
                    if (hit.page > 0)
                      context.l10n.tr(
                        '第 ${hit.page} 页',
                        en: 'Page ${hit.page}',
                      ),
                  ].join(' · ');
                  return Material(
                    color:
                        scheme.surfaceContainerHighest.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(18),
                    child: ListTile(
                      key: ValueKey('image-search-candidate-$index'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      leading: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          '${hit.similarity.round()}%',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      title: Text(
                        hit.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        isJm ? Icons.menu_book_rounded : Icons.search_rounded,
                        color: scheme.primary,
                      ),
                      onTap: () => Navigator.of(context).pop(hit),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      context.l10n.tr(
                        '识图由 soutubot.moe 提供；图片会发送至该服务进行本次识别。',
                        en: 'Recognition is provided by soutubot.moe; the image is sent there for this search.',
                      ),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _imageLanguageLabel(String value) {
  switch (value.toLowerCase()) {
    case 'zh':
    case 'cn':
    case 'chinese':
      return '中文';
    case 'ja':
    case 'jp':
    case 'japanese':
      return '日文';
    case 'en':
    case 'gb':
    case 'english':
      return '英文';
    case 'ko':
    case 'kr':
    case 'korean':
      return '韩文';
    default:
      return value;
  }
}

class _SuggestionPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SuggestionPill({
    required this.label,
    required this.onTap,
    this.icon,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .58),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
