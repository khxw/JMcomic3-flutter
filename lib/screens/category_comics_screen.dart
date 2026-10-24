import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_pager.dart';

import 'components/browser_bottom_sheet.dart';

class CategoryComicsScreen extends StatefulWidget {
  final Categories category;
  final SortBy sortBy;

  const CategoryComicsScreen({
    required this.category,
    this.sortBy = sortByNew,
    super.key,
  });

  @override
  State<CategoryComicsScreen> createState() => _CategoryComicsScreenState();
}

class _CategoryComicsScreenState extends State<CategoryComicsScreen> {
  late SortBy _sortBy = widget.sortBy;

  Future<void> _chooseSort() async {
    final selected = await chooseMapDialog<SortBy>(
      context,
      values: {
        for (final sort in sorts) sortByName(context, sort): sort,
      },
      title: context.l10n.tr('选择排序方式', en: 'Choose sort order'),
      tips: context.l10n.tr(
        '切换排序后会从第一页重新加载。',
        en: 'Changing the sort reloads results from the first page.',
      ),
    );
    if (selected == null || selected == _sortBy || !mounted) return;
    setState(() => _sortBy = selected);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey('category-comics-screen'),
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(widget.category.name),
        surfaceTintColor: Colors.transparent,
        actions: const [BrowserBottomSheetAction()],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CategoryToolbar(
              sortBy: _sortBy,
              onSort: _chooseSort,
            ),
            Expanded(
              child: ComicPager(
                key: ValueKey(
                  'category:${widget.category.slug}:${_sortBy.value}',
                ),
                onPage: (page) async {
                  final response = await methods.comics(
                    widget.category.slug,
                    _sortBy,
                    page,
                  );
                  return InnerComicPage(
                    total: response.total,
                    list: response.content,
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

class _CategoryToolbar extends StatelessWidget {
  final SortBy sortBy;
  final VoidCallback onSort;

  const _CategoryToolbar({
    required this.sortBy,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.tr(
                '浏览全部漫画',
                en: 'Browse all comics',
              ),
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(99),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('category-sort-button'),
              onTap: onSort,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sort_rounded,
                      size: 17,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${context.l10n.tr('排序', en: 'Sort')} · '
                      '${sortByName(context, sortBy)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
