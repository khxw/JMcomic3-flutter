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
      _categoryNotifier.value = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.weekMustSee),
      ),
      body: ContentBuilder<WeekData>(
        future: _weekData,
        onRefresh: _refresh,
        successBuilder: (context, data) {
          final weekData = data.requireData;
          final selectedCategoryId =
              _resolveCategoryId(weekData.categories, _categoryNotifier.value);
          return WeekContent(
            key: ValueKey(
              'week_content_${weekData.categories.length}_${weekData.types.length}',
            ),
            data: weekData,
            initialCategoryId: selectedCategoryId,
            categoryNotifier: _categoryNotifier,
            onCategoryChanged: (_) {},
          );
        },
      ),
    );
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
    widget.categoryNotifier.addListener(_onCategoryNotifierChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _categoryId.isEmpty) {
        return;
      }
      if (widget.categoryNotifier.value != _categoryId) {
        widget.categoryNotifier.value = _categoryId;
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
        if (widget.categoryNotifier.value != _categoryId) {
          widget.categoryNotifier.value = _categoryId;
        }
        widget.onCategoryChanged(_categoryId);
      }
    }
  }

  @override
  void dispose() {
    widget.categoryNotifier.removeListener(_onCategoryNotifierChanged);
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
    final issueChipHeight = math.max(
      38.0,
      MediaQuery.textScalerOf(context).scale(12.5) + 18,
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
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: SizedBox(
              key: const ValueKey('week-issue-selector'),
              height: issueChipHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: widget.data.categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = widget.data.categories[index];
                  final selected = category.id == _categoryId;
                  final chip = Material(
                    key: ValueKey('week-issue-choice-${category.id}'),
                    color: selected
                        ? scheme.primary
                        : scheme.surfaceContainerLow.withValues(alpha: .92),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                      side: BorderSide(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant.withValues(alpha: .5),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _selectCategory(category.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              selected
                                  ? Icons.calendar_month_rounded
                                  : Icons.calendar_today_outlined,
                              size: 15,
                              color: selected
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              category.time,
                              maxLines: 1,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: selected
                                        ? scheme.onPrimary
                                        : scheme.onSurfaceVariant,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                  if (category.title.trim().isEmpty) return chip;
                  return Tooltip(
                    message: category.title.trim(),
                    child: chip,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
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
    _selectCategory(nextId);
    defaultToast(context, context.l10n.switchedToNextIssue);
  }

  void _selectCategory(String nextId) {
    if (nextId == _categoryId) return;
    if (!widget.data.categories.any((category) => category.id == nextId)) {
      return;
    }
    setState(() {
      _categoryId = nextId;
    });
    if (widget.categoryNotifier.value != nextId) {
      widget.categoryNotifier.value = nextId;
    }
    widget.onCategoryChanged(nextId);
  }

  void _onCategoryNotifierChanged() {
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
