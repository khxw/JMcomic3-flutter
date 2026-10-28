import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_pager.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';

import '../basic/methods.dart';

class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  late Future<WeekData> _weekData;
  final ValueNotifier<String?> _categoryNotifier = ValueNotifier<String?>(null);

  List<WeekCategory> _categories = const [];
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _weekData = methods.week(0);
  }

  @override
  void dispose() {
    _categoryNotifier.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _weekData = methods.week(0);
      _categories = const [];
      _categoryId = null;
      _categoryNotifier.value = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.weekMustSee),
        actions: [
          if (_categories.isNotEmpty && _categoryId != null)
            _buildCategorySelector(context),
        ],
      ),
      body: ContentBuilder<WeekData>(
        future: _weekData,
        onRefresh: _refresh,
        successBuilder: (context, data) {
          final weekData = data.requireData;
          final selectedCategoryId =
              _resolveCategoryId(weekData.categories, _categoryId);
          if (!_sameCategories(_categories, weekData.categories) ||
              _categoryId != selectedCategoryId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              _syncAppBarState(weekData.categories, selectedCategoryId);
            });
          }
          return WeekContent(
            key: ValueKey(
              'week_content_${weekData.categories.length}_${weekData.types.length}',
            ),
            data: weekData,
            initialCategoryId: selectedCategoryId,
            categoryNotifier: _categoryNotifier,
            onCategoryChanged: (value) {
              _syncAppBarState(weekData.categories, value);
            },
          );
        },
      ),
    );
  }

  Widget _buildCategorySelector(BuildContext context) {
    final selectedCategoryId = _resolveCategoryId(_categories, _categoryId);
    if (selectedCategoryId == null) {
      return const SizedBox.shrink();
    }
    final textStyle = _categorySelectorTextStyle(context);
    final selectorWidth = _calcCategorySelectorWidth(context, textStyle);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: SizedBox(
          width: selectorWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: .7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedCategoryId,
                  isDense: true,
                  isExpanded: true,
                  iconSize: 18,
                  style: textStyle,
                  borderRadius: BorderRadius.circular(12),
                  menuMaxHeight: 420,
                  selectedItemBuilder: (context) {
                    return _categories
                        .map(
                          (e) => Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                e.time,
                                maxLines: 1,
                                style: textStyle,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false);
                  },
                  items: _categories
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(
                            e.time,
                            style: textStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null || value == _categoryId) {
                      return;
                    }
                    setState(() {
                      _categoryId = value;
                      _categoryNotifier.value = value;
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _categorySelectorTextStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return base.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      height: 1.1,
    );
  }

  double _calcCategorySelectorWidth(BuildContext context, TextStyle textStyle) {
    final textDirection = Directionality.of(context);
    var longestWidth = 0.0;
    for (final category in _categories) {
      final painter = TextPainter(
        text: TextSpan(text: category.time, style: textStyle),
        maxLines: 1,
        textDirection: textDirection,
      )..layout();
      longestWidth = math.max(longestWidth, painter.width);
    }
    // 文字宽度 + 左右内边距 + 下拉图标空间。
    final preferredWidth = longestWidth + 46;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = screenWidth * .52;
    return preferredWidth.clamp(126.0, maxWidth).toDouble();
  }

  void _syncAppBarState(List<WeekCategory> categories, String? selectedId) {
    final nextId = _resolveCategoryId(categories, selectedId);
    if (categories.isEmpty || nextId == null) {
      if (_categories.isEmpty && _categoryId == null) {
        return;
      }
      setState(() {
        _categories = const [];
        _categoryId = null;
        _categoryNotifier.value = null;
      });
      return;
    }

    final changed =
        !_sameCategories(_categories, categories) || _categoryId != nextId;
    if (changed) {
      setState(() {
        _categories = List<WeekCategory>.unmodifiable(categories);
        _categoryId = nextId;
      });
    }
    if (_categoryNotifier.value != nextId) {
      _categoryNotifier.value = nextId;
    }
  }

  static String? _resolveCategoryId(
    List<WeekCategory> categories,
    String? candidate,
  ) {
    if (categories.isEmpty) {
      return null;
    }
    if (candidate != null &&
        categories.any((element) => element.id == candidate)) {
      return candidate;
    }
    return categories.first.id;
  }

  static bool _sameCategories(List<WeekCategory> a, List<WeekCategory> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].time != b[i].time) {
        return false;
      }
    }
    return true;
  }
}

class _IssueHeader extends StatelessWidget {
  final WeekCategory category;
  final int issueCount;

  const _IssueHeader({
    required this.category,
    required this.issueCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = category.title.trim().isEmpty
        ? context.l10n.weekMustSee
        : category.title.trim();
    return Container(
      key: const ValueKey('week-issue-header'),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.primary.withValues(alpha: .16),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary,
                  scheme.tertiary,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: scheme.onPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: .1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.l10n.tr(
                    '${category.time} · $issueCount 期',
                    en: '${category.time} · $issueCount ${issueCount == 1 ? 'issue' : 'issues'}',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              context.l10n.tr('每周精选', en: 'Weekly'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WeekContent extends StatefulWidget {
  final WeekData data;
  final String? initialCategoryId;
  final ValueNotifier<String?> categoryNotifier;
  final ValueChanged<String> onCategoryChanged;

  const WeekContent({
    super.key,
    required this.data,
    required this.initialCategoryId,
    required this.categoryNotifier,
    required this.onCategoryChanged,
  });

  @override
  State<WeekContent> createState() => _WeekContentState();
}

class _WeekContentState extends State<WeekContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<WeekType> _displayTypes;
  late String _categoryId;
  late String _typeId;

  @override
  void initState() {
    super.initState();
    _displayTypes = _buildDisplayTypes(widget.data.types);
    _categoryId = _resolveInitialCategoryId();
    _typeId = _displayTypes.isNotEmpty ? _displayTypes.first.id : '';
    _tabController = _createTabController(preferredTypeId: _typeId);
    widget.categoryNotifier.addListener(_onCategoryChangedFromAppBar);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _categoryId.isEmpty) {
        return;
      }
      widget.onCategoryChanged(_categoryId);
    });
  }

  @override
  void didUpdateWidget(covariant WeekContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_needsRebuildTypes(oldWidget.data.types, widget.data.types)) {
      _displayTypes = _buildDisplayTypes(widget.data.types);
      final keepType = _typeId;
      _tabController.dispose();
      _tabController = _createTabController(preferredTypeId: keepType);
      _typeId = _displayTypes.isNotEmpty &&
              _displayTypes.any((element) => element.id == keepType)
          ? keepType
          : (_displayTypes.isNotEmpty ? _displayTypes.first.id : '');
    }
    final resolvedCategoryId = _resolveInitialCategoryId();
    if (resolvedCategoryId != _categoryId) {
      _categoryId = resolvedCategoryId;
      if (_categoryId.isNotEmpty) {
        widget.onCategoryChanged(_categoryId);
      }
    }
  }

  @override
  void dispose() {
    widget.categoryNotifier.removeListener(_onCategoryChangedFromAppBar);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.categories.isEmpty || _displayTypes.isEmpty) {
      return Center(
        child: Text(context.l10n.noContentAvailable),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final selectedCategory = widget.data.categories.firstWhere(
      (category) => category.id == _categoryId,
      orElse: () => widget.data.categories.first,
    );
    final typeTabHeight = math.max(
      36.0,
      MediaQuery.textScalerOf(context).scale(12.5) + 18,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: .07),
            scheme.surface,
          ],
          stops: const [0, .34],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _IssueHeader(
              category: selectedCategory,
              issueCount: widget.data.categories.length,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              key: const ValueKey('week-type-selector'),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow.withValues(alpha: .86),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: .42),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                padding: const EdgeInsets.all(4),
                labelPadding: const EdgeInsets.symmetric(horizontal: 13),
                labelColor: scheme.onPrimary,
                unselectedLabelColor: scheme.onSurfaceVariant,
                labelStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                splashBorderRadius: BorderRadius.circular(12),
                overlayColor: WidgetStatePropertyAll(
                  scheme.primary.withValues(alpha: .08),
                ),
                tabs: _displayTypes
                    .map(
                      (type) => Tab(
                        key: ValueKey('week-type-${type.id}'),
                        height: typeTabHeight,
                        text: type.title,
                      ),
                    )
                    .toList(growable: false),
                onTap: (index) {
                  final nextTypeId = _displayTypes[index].id;
                  if (nextTypeId == _typeId) {
                    return;
                  }
                  setState(() {
                    _typeId = nextTypeId;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: ColoredBox(
                color: scheme.surface.withValues(alpha: .82),
                child: ComicPager(
                  key: ValueKey('week_filter_${_categoryId}_$_typeId'),
                  onPage: _onPage,
                  appendList: widget.data.categories.length > 1
                      ? [
                          _buildNextCard(),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<InnerComicPage> _onPage(int page) async {
    // 分页缓存统一交给 ComicPager 管理；重复缓存会让分页器的强制刷新再次返回旧结果。
    final response = await methods.weekFilter(_categoryId, _typeId, page);
    return InnerComicPage(
      total: response.total,
      list: response.list,
    );
  }

  Widget _buildNextCard() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: .56),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.primary.withValues(alpha: .24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _switchToNextCategory,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.arrow_forward_rounded,
              color: scheme.primary,
            ),
            const SizedBox(height: 7),
            Text(
              context.l10n.nextIssue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _switchToNextCategory() {
    final currentIndex =
        widget.data.categories.indexWhere((item) => item.id == _categoryId);
    if (currentIndex < 0 || currentIndex + 1 >= widget.data.categories.length) {
      defaultToast(context, context.l10n.noMoreIssue);
      return;
    }
    final nextId = widget.data.categories[currentIndex + 1].id;
    setState(() {
      _categoryId = nextId;
    });
    widget.categoryNotifier.value = nextId;
    widget.onCategoryChanged(nextId);
    defaultToast(context, context.l10n.switchedToNextIssue);
  }

  void _onCategoryChangedFromAppBar() {
    final value = widget.categoryNotifier.value;
    if (value == null || value == _categoryId) {
      return;
    }
    final exists = widget.data.categories.any((element) => element.id == value);
    if (!exists) {
      return;
    }
    setState(() {
      _categoryId = value;
    });
  }

  String _resolveInitialCategoryId() {
    final fallback = widget.data.categories.isNotEmpty
        ? widget.data.categories.first.id
        : '';
    final candidate = widget.initialCategoryId;
    if (candidate == null || candidate.isEmpty) {
      return fallback;
    }
    return widget.data.categories.any((element) => element.id == candidate)
        ? candidate
        : fallback;
  }

  List<WeekType> _buildDisplayTypes(List<WeekType> types) {
    return types.reversed.toList(growable: false);
  }

  TabController _createTabController({required String preferredTypeId}) {
    final preferredIndex =
        _displayTypes.indexWhere((element) => element.id == preferredTypeId);
    final initialIndex = preferredIndex >= 0 ? preferredIndex : 0;
    return TabController(
      length: _displayTypes.length,
      vsync: this,
      initialIndex: initialIndex,
    );
  }

  bool _needsRebuildTypes(List<WeekType> oldTypes, List<WeekType> newTypes) {
    if (oldTypes.length != newTypes.length) {
      return true;
    }
    for (var i = 0; i < oldTypes.length; i++) {
      if (oldTypes[i].id != newTypes[i].id ||
          oldTypes[i].title != newTypes[i].title) {
        return true;
      }
    }
    return false;
  }
}
