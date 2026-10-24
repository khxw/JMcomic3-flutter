import 'dart:async';

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

  const SearchScreen({this.active = true, Key? key}) : super(key: key);

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
  SortBy _sortBy = sortByDefault;
  bool _loadingSuggestions = true;
  bool _suggestionsLoaded = false;
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

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _submit([String? value]) {
    final query = (value ?? _controller.text).trim();
    if (query.isEmpty) return;
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _focusNode.unfocus();
    setState(() {
      _query = query;
    });
  }

  void _clearQuery() {
    _controller.clear();
    setState(() {
      _query = '';
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
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
                      if (Navigator.of(context).canPop()) ...[
                        IconButton.filledTonal(
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.navSearch,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -.4,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              context.l10n.tr(
                                '按标题、作者或标签发现漫画',
                                en: 'Find comics by title, author or tag',
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
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
            builder: (context, value, _) => value.text.isEmpty
                ? IconButton(
                    tooltip: context.l10n.navSearch,
                    onPressed: _submit,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  )
                : IconButton(
                    tooltip: context.l10n.tr('清除', en: 'Clear'),
                    onPressed: _clearQuery,
                    icon: const Icon(Icons.close_rounded),
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
                tooltip: context.l10n.tr(
                  '清除所有历史记录',
                  en: 'Clear all search history',
                ),
                onPressed: _clearSearchHistory,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < _histories.length; index++)
                _SuggestionPill(
                  label: _histories[index].searchQuery,
                  icon: Icons.north_west_rounded,
                  onTap: () => _submit(_histories[index].searchQuery),
                  onLongPress: () => _removeSearchHistory(_histories[index]),
                ),
            ],
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
    return Column(
      key: ValueKey('search-results:$_query:$_sortBy'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.tr(
                    '“$_query”的搜索结果',
                    en: 'Results for “$_query”',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton.filledTonal(
                tooltip:
                    '${context.l10n.chooseSort}: ${sortByName(context, _sortBy)}',
                onPressed: () async {
                  final value = await chooseSortBy(context);
                  if (!mounted || value == null) return;
                  setState(() {
                    _sortBy = value;
                  });
                },
                icon: const Icon(Icons.sort_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: ComicPager(
            key: Key("search-tab:$_query:$_sortBy"),
            onPage: (page) async {
              final response = await methods.comicSearch(_query, _sortBy, page);
              return InnerComicPage(
                total: response.total,
                list: response.content,
                redirectAid: response.redirectAid,
              );
            },
          ),
        ),
      ],
    );
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
