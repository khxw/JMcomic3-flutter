import 'dart:convert';

import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_error.dart';

import '../basic/methods.dart';
import '../screens/components/app_back_button.dart';
import 'property_json.dart';

List<int> _categoriesSort = const <int>[];

sortCategories(List<Categories> categories) {
  _sortCategoriesByOrder(categories, _categoriesSort);
}

List<int> getCategoriesSort() {
  return _categoriesSort;
}

const _propertyName = "categoriesSort";

Future initCategoriesSort() async {
  try {
    final raw = await methods.loadProperty(_propertyName);
    _categoriesSort = _decodeCategoriesSort(raw);
  } catch (_) {
    _categoriesSort = const <int>[];
  }
  // 首页可能先于配置初始化完成；这里主动通知一次，避免冷启动首屏使用
  // 服务端默认顺序，直到用户进入设置页才看到保存的自定义顺序。
  categoriesSortEvent.broadcast();
}

get categoriesSort => _categoriesSort;
var categoriesSortEvent = Event();

Future<dynamic> saveCategoriesSort(List<int> categories) async {
  // 排序配置会被写入本地属性和 WebDAV 快照；保存前统一去重/过滤，避免脏值长期传播。
  final normalized = _normalizeCategoriesSortValues(categories);
  _categoriesSort = List<int>.unmodifiable(normalized);
  await methods.saveProperty(_propertyName, jsonEncode(normalized));
  categoriesSortEvent.broadcast();
}

List<int> _decodeCategoriesSort(String raw) {
  var candidate = raw;
  for (var depth = 0; depth <= 2; depth++) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty || !looksLikeJsonPropertyValue(trimmed)) {
      return const <int>[];
    }
    final decoded = tryDecodeJsonPropertyValue(trimmed);
    if (decoded is Iterable) {
      // 旧版本或手工编辑的排序配置可能包含重复、空值、字符串数字或非法项；
      // 初始化时只保留有效非负整数 ID，避免首页分类排序因本地脏数据失败。
      return List<int>.unmodifiable(_normalizeCategoriesSortValues(decoded));
    }
    if (decoded is String && depth < 2) {
      // WebDAV/脚本迁移可能把排序数组再 JSON 编码；最多拆两层字符串包装，
      // 与其他配置项保持一致，同时避免损坏值导致无界递归。
      candidate = decoded;
      continue;
    }
    return const <int>[];
  }
  return const <int>[];
}

List<int> _normalizeCategoriesSortValues(
  Iterable<dynamic> values, {
  Set<int>? allowedIds,
}) {
  final result = <int>[];
  final seen = <int>{};
  for (final item in values) {
    final id = _parseCategoryId(item);
    if (id == null || !seen.add(id)) {
      continue;
    }
    if (allowedIds != null && !allowedIds.contains(id)) {
      continue;
    }
    result.add(id);
  }
  return result;
}

/// 分类排序面板只应带入当前仍存在的分类 ID。
/// 旧缓存或远端同步过来的排序可能包含已下线分类；进入编辑页时过滤它们，保存后自然收敛。
List<int> restoreCategoriesSortSelection(
  List<int> savedSort,
  Iterable<Categories> categories,
) {
  final liveIds = categories.map((category) => category.id).toSet();
  return _normalizeCategoriesSortValues(savedSort, allowedIds: liveIds);
}

int? _parseCategoryId(dynamic raw) {
  int? parsed;
  if (raw is int) {
    parsed = raw;
  } else if (raw is num && raw.isFinite && raw == raw.truncateToDouble()) {
    parsed = raw.toInt();
  } else if (raw is String) {
    final trimmed = raw.trim();
    parsed = int.tryParse(trimmed);
    if (parsed == null) {
      final numeric = num.tryParse(trimmed);
      if (numeric != null &&
          numeric.isFinite &&
          numeric == numeric.truncateToDouble()) {
        parsed = numeric.toInt();
      }
    }
  }
  // “最新 A 漫”等内置入口使用 ID 0，不能像负数那样被过滤。
  return parsed != null && parsed >= 0 ? parsed : null;
}

void _sortCategoriesByOrder(List<Categories> categories, List<int> sort) {
  final originalIndex = <int, int>{};
  for (var index = 0; index < categories.length; index++) {
    originalIndex.putIfAbsent(categories[index].id, () => index);
  }
  final sortIndex = <int, int>{};
  for (var index = 0; index < sort.length; index++) {
    sortIndex.putIfAbsent(sort[index], () => index);
  }

  categories.sort((a, b) {
    final aIndex = sortIndex[a.id];
    final bIndex = sortIndex[b.id];
    if (aIndex == null && bIndex == null) {
      return (originalIndex[a.id] ?? 0).compareTo(originalIndex[b.id] ?? 0);
    }
    if (aIndex == null) {
      return 1;
    }
    if (bIndex == null) {
      return -1;
    }
    return aIndex.compareTo(bIndex);
  });
}

Widget categoriesSortSetting(BuildContext context) {
  return ListTile(
    key: const ValueKey('settings-categories-sort'),
    leading: const Icon(Icons.swap_vert_rounded),
    onTap: () {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (BuildContext context) {
          return const CategoriesSortScreen();
        },
      ));
    },
    title: Text(
      context.l10n.tr("首页分类排序", en: "Homepage category order"),
    ),
    subtitle: Text(
      context.l10n.tr(
        '拖动调整首页分类顺序',
        en: 'Drag to reorder homepage categories',
      ),
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
  );
}

class CategoriesSortScreen extends StatefulWidget {
  const CategoriesSortScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CategoriesSortScreenState();
}

class _CategoriesSortScreenState extends State<CategoriesSortScreen> {
  Future<CategoriesResponse> _categoriesFuture = methods.categories();
  Key _key = UniqueKey();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        key: _key,
        future: _categoriesFuture,
        builder:
            (BuildContext context, AsyncSnapshot<CategoriesResponse> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: AppBar(
                leading: const AppBackButton(),
                title: Text(context.l10n.tr("分类排序", en: "Category order")),
              ),
              body: const Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(
                leading: const AppBackButton(),
                title: Text(context.l10n.tr("分类排序", en: "Category order")),
              ),
              body: ContentError(
                error: snapshot.error,
                stackTrace: snapshot.stackTrace,
                onRefresh: () async {
                  setState(() {
                    _categoriesFuture = methods.categories();
                    _key = UniqueKey();
                  });
                },
              ),
            );
          }
          var categories = snapshot.requireData.categories;
          return CategoriesSortPanel(categories);
        });
  }
}

class CategoriesSortPanel extends StatefulWidget {
  final List<Categories> categories;

  const CategoriesSortPanel(this.categories, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CategoriesSortPanelState();
}

class _CategoriesSortPanelState extends State<CategoriesSortPanel> {
  late final List<int> _defaultOrder;
  late final Map<int, Categories> _categoriesById;
  late List<int> _categoriesSort;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _categoriesById = {
      for (final category in widget.categories) category.id: category,
    };
    _defaultOrder = _categoriesById.keys.toList(growable: false);
    final saved = restoreCategoriesSortSelection(
      getCategoriesSort(),
      widget.categories,
    );
    _categoriesSort = [
      ...saved,
      ..._defaultOrder.where((id) => !saved.contains(id)),
    ];
  }

  void _reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _categoriesSort.length) return;
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= _categoriesSort.length) return;
    setState(() {
      final id = _categoriesSort.removeAt(oldIndex);
      _categoriesSort.insert(newIndex, id);
    });
  }

  void _restoreDefaultOrder() {
    setState(() {
      _categoriesSort = List<int>.of(_defaultOrder);
    });
  }

  bool get _isDefaultOrder {
    if (_categoriesSort.length != _defaultOrder.length) return false;
    for (var index = 0; index < _defaultOrder.length; index++) {
      if (_categoriesSort[index] != _defaultOrder[index]) return false;
    }
    return true;
  }

  String? _categoryMetadata(BuildContext context, Categories category) {
    final parts = <String>[];
    final slug = category.slug.trim();
    if (slug.isNotEmpty) parts.add(slug);
    if (category.totalAlbums > 0) {
      parts.add(
        context.l10n.tr(
          '${category.totalAlbums} 本',
          en: '${category.totalAlbums} comics',
        ),
      );
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await saveCategoriesSort(_categoriesSort);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr(
              '保存分类排序失败，请重试',
              en: 'Could not save category order. Try again.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_categoriesSort.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: Text(context.l10n.tr('分类排序', en: 'Category order')),
        ),
        body: Center(
          child: Text(
            context.l10n.tr(
              '暂无可排序的首页分类',
              en: 'No homepage categories available',
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.l10n.tr('分类排序', en: 'Category order')),
        actions: [
          IconButton(
            key: const ValueKey('category-sort-reset'),
            tooltip: context.l10n.tr('恢复默认', en: 'Restore default'),
            onPressed: _isDefaultOrder ? null : _restoreDefaultOrder,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        key: const ValueKey('category-sort-list'),
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        itemCount: _categoriesSort.length,
        onReorder: _reorder,
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, child) {
              return Material(
                color: Colors.transparent,
                elevation: 8 * animation.value,
                borderRadius: BorderRadius.circular(17),
                child: child,
              );
            },
          );
        },
        header: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.drag_indicator_rounded,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.tr(
                          '共 ${_categoriesSort.length} 个分类',
                          en: '${_categoriesSort.length} categories',
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.tr(
                          '按住右侧手柄拖动排序，保存后首页立即更新。',
                          en: 'Hold the handle to reorder. Home updates after saving.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        itemBuilder: (context, index) {
          final id = _categoriesSort[index];
          final category = _categoriesById[id];
          if (category == null) return const SizedBox.shrink(key: ValueKey(-1));
          final metadata = _categoryMetadata(context, category);
          return Padding(
            key: ValueKey('category-sort-${category.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(17),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                title: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: metadata == null
                    ? null
                    : Text(
                        metadata,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          key: const ValueKey('category-sort-save'),
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(
            _saving
                ? context.l10n.tr('正在保存...', en: 'Saving...')
                : context.l10n.tr('保存排序', en: 'Save order'),
          ),
        ),
      ),
    );
  }
}
