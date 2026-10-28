import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';
import 'package:jmcomic3/screens/components/week_comic_feed.dart';

import '../basic/methods.dart';
import 'components/app_back_button.dart';

class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  late Future<WeekData> _weekData;
  final ValueNotifier<String?> _categoryNotifier = ValueNotifier<String?>(null);
  List<WeekCategory> _categories = const [];
  String? _selectedCategoryId;

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
      _categories = const [];
      _selectedCategoryId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          leading: const AppBackButton(),
          title: Text(context.l10n.weekMustSee),
          actions: [
            if (_categories.isNotEmpty && _selectedCategoryId != null)
              _issueMenu(context),
          ],
        ),
        body: ContentBuilder<WeekData>(
          future: _weekData,
          onRefresh: _refresh,
          successBuilder: (context, data) {
            final weekData = data.requireData;
            final selectedCategoryId =
                _resolveCategoryId(weekData.categories, _selectedCategoryId);
            if (!_sameCategories(_categories, weekData.categories) ||
                _selectedCategoryId != selectedCategoryId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _categories =
                      List<WeekCategory>.unmodifiable(weekData.categories);
                  _selectedCategoryId = selectedCategoryId;
                });
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
                if (!mounted || _selectedCategoryId == value) return;
                setState(() => _selectedCategoryId = value);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _issueMenu(BuildContext context) {
    final categories = _categories;
    final selectedIndex =
        categories.indexWhere((item) => item.id == _selectedCategoryId);
    final selected = categories[selectedIndex < 0 ? 0 : selectedIndex];
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        key: const ValueKey('week-issue-menu'),
        tooltip: context.l10n.tr('选择期数', en: 'Choose an issue'),
        onSelected: (value) {
          if (value == _selectedCategoryId) return;
          setState(() => _selectedCategoryId = value);
          _categoryNotifier.value = value;
        },
        itemBuilder: (context) => categories
            .map(
              (category) => PopupMenuItem<String>(
                value: category.id,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        category.time,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (category.id == selected.id)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
        child: Container(
          height: 36,
          constraints: const BoxConstraints(maxWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .64),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .42),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_rounded, size: 18, color: scheme.onSurface),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  selected.time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
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

  static bool _sameCategories(List<WeekCategory> a, List<WeekCategory> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].id != b[index].id || a[index].time != b[index].time) {
        return false;
      }
    }
    return true;
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

class _WeekContentState extends State<WeekContent> {
  late List<WeekType> _displayTypes;
  late String _categoryId;
  late String _typeId;

  @override
  void initState() {
    super.initState();
    _displayTypes = _buildDisplayTypes(widget.data.types);
    _categoryId = _resolveInitialCategoryId();
    _typeId = _displayTypes.isNotEmpty ? _displayTypes.first.id : '';
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
    final typeChipHeight = math.max(
      36.0,
      MediaQuery.textScalerOf(context).scale(12.5) + 18,
    );
    return Column(
      children: [
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            key: const ValueKey('week-type-selector'),
            height: typeChipHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _displayTypes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final type = _displayTypes[index];
                final selected = type.id == _typeId;
                return Material(
                  key: ValueKey('week-type-${type.id}'),
                  color: selected
                      ? scheme.primary
                      : scheme.surfaceContainerLow.withValues(alpha: .9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: BorderSide(
                      color: selected
                          ? scheme.primary
                          : scheme.outlineVariant.withValues(alpha: .48),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      if (type.id == _typeId) return;
                      setState(() {
                        _typeId = type.id;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: Text(
                          _typeLabel(type),
                          maxLines: 1,
                          style: TextStyle(
                            color: selected
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                            fontSize: 12.5,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: ColoredBox(
              color: scheme.surface.withValues(alpha: .82),
              child: WeekComicFeed(
                key: ValueKey('week_feed_${_categoryId}_$_typeId'),
                categoryId: _categoryId,
                typeId: _typeId,
              ),
            ),
          ),
        ),
      ],
    );
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

  String _typeLabel(WeekType type) {
    final title = type.title.trim();
    if (title.isNotEmpty) return title;
    final id = type.id.trim().toLowerCase();
    if (id == 'hanman' || id == 'han' || id == 'kr') {
      return context.l10n.tr('韩漫', en: 'Korean comics');
    }
    if (id.isNotEmpty) return id.toUpperCase();
    return context.l10n.tr('榜单', en: 'Ranking');
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
