import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_pager.dart';

import 'components/app_back_button.dart';
import 'components/right_click_pop.dart';
import 'components/types.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({Key? key, this.embedded = false}) : super(key: key);

  final bool embedded;

  @override
  State<StatefulWidget> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  int _folderId = 0;

  final Map<int, String> _folderMap = {
    0: "",
  };

  _chooseFolder() async {
    _folderMap[0] = context.l10n.all;
    int? f = await chooseMapDialog(
      context,
      values: _folderMap.map((key, value) => MapEntry(value, key)),
      title: context.l10n.chooseFolder,
    );
    if (f != null) {
      setState(() {
        _folderId = f;
      });
    }
  }

  Future<void> _reloadFavoriteFolders() async {
    final response = await methods.favorite();
    favData = response.folderList;
    if (!mounted) return;
    setState(() {
      _folderMap
        ..clear()
        ..addAll({
          0: context.l10n.all,
          for (final folder in response.folderList) folder.fid: folder.name,
        });
    });
  }

  Future<void> _moveFavoriteToFolder(ComicBasic comic) async {
    final targets = <String, int>{
      context.l10n.tr('默认收藏夹', en: 'Default favorites'): 0,
      for (final entry in _folderMap.entries)
        if (entry.key != 0) entry.value: entry.key,
      context.l10n.tr('新建收藏夹...', en: 'New favorites folder...'): -1,
    };
    var target = await chooseMapDialog<int>(
      context,
      values: targets,
      title: context.l10n.tr(
        '移动“${comic.name}”到',
        en: 'Move "${comic.name}" to',
      ),
    );
    if (target == null || !mounted) return;
    if (target == -1) {
      final name = await displayTextInputDialog(
        context,
        title: context.l10n.tr('新建收藏夹', en: 'New favorites folder'),
        hint: context.l10n.tr('文件夹名称', en: 'Folder name'),
      );
      if (name == null || name.trim().isEmpty || !mounted) return;
      try {
        await methods.createFavoriteFolder(name.trim());
        await _reloadFavoriteFolders();
        int? createdId;
        for (final folder in favData.reversed) {
          if (folder.name == name.trim()) {
            createdId = folder.fid;
            break;
          }
        }
        if (createdId == null) {
          throw StateError('Created folder was not returned');
        }
        target = createdId;
      } catch (error) {
        if (mounted) {
          defaultToast(context, context.l10n.tr('新建收藏夹失败：$error'));
        }
        return;
      }
    }
    try {
      await methods.comicFavoriteFolderMove(comic.id, target);
      if (!mounted) return;
      setState(() {
        _total = -1;
        _refreshGeneration++;
      });
      defaultToast(
        context,
        context.l10n.tr('已移动到收藏夹', en: 'Moved to favorites folder'),
      );
    } catch (error) {
      if (mounted) {
        defaultToast(context, context.l10n.tr('移动收藏失败：$error'));
      }
    }
  }

  String _sort = "mr";
  var _refreshGeneration = 0;
  var _total = -1;

  Map<String, String> _sortNameMap(BuildContext context) {
    return {
      "mr": context.l10n.sortByFavoriteTime,
      "mp": context.l10n.sortByUpdateTime,
    };
  }

  _chooseSort() async {
    final nameMap = _sortNameMap(context);
    String? f = await chooseMapDialog(
      context,
      values: nameMap.map((key, value) => MapEntry(value, key)),
      title: context.l10n.chooseSort,
    );
    if (f != null) {
      setState(() {
        _sort = f;
      });
      await methods.saveProperty("favorites_sort", f);
    }
  }

  @override
  void initState() {
    for (var value in favData) {
      try {
        _folderMap[value.fid] = value.name;
      } catch (e) {
        debugPrient(e);
        defaultToast(context, "$e");
      }
    }
    _loadSort();
    super.initState();
  }

  Future<void> _loadSort() async {
    try {
      final sort = await methods.loadProperty("favorites_sort");
      if (!mounted) return;
      if (sort.isNotEmpty &&
          sort != _sort &&
          _sortNameMap(context).containsKey(sort)) {
        setState(() {
          _sort = sort;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    _folderMap[0] = context.l10n.all;
    if (widget.embedded) {
      return rightClickPop(
        child: _buildEmbedded(context),
        context: context,
      );
    }
    final sortNameMap = _sortNameMap(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.l10n.favorites),
        actions: [
          IconButton(
            onPressed: _chooseSort,
            tooltip: "${context.l10n.chooseSort}: ${sortNameMap[_sort] ?? ""}",
            icon: const Icon(Icons.sort),
          ),
          IconButton(
            onPressed: _chooseFolder,
            tooltip:
                "${context.l10n.chooseFolder}: ${_folderMap[_folderId] ?? context.l10n.all}",
            icon: const Icon(Icons.folder_copy_outlined),
          ),
        ],
      ),
      body: _buildPager(context),
    );
  }

  Widget _buildEmbedded(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sortNameMap = _sortNameMap(context);
    final folderName = _folderMap[_folderId] ?? context.l10n.all;
    final sortName = sortNameMap[_sort] ?? '';
    final countLabel = _total < 0
        ? context.l10n.tr('正在同步收藏', en: 'Syncing favorites')
        : context.l10n.tr(
            '$_total 部收藏',
            en: '$_total ${_total == 1 ? 'favorite' : 'favorites'}',
          );
    return Column(
      key: const ValueKey('bookshelf-online-content'),
      children: [
        Container(
          key: const ValueKey('favorites-overview'),
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .45),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 20,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$countLabel · $sortName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('favorites-refresh'),
                    onPressed: () {
                      setState(() {
                        _total = -1;
                        _refreshGeneration++;
                      });
                    },
                    tooltip: context.l10n.tr('刷新收藏', en: 'Refresh favorites'),
                    icon: const Icon(Icons.refresh_rounded, size: 21),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('favorites-sort'),
                      onPressed: _chooseSort,
                      icon: const Icon(Icons.sort_rounded, size: 18),
                      label: Text(
                        sortName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('favorites-folder'),
                      onPressed: _chooseFolder,
                      icon: const Icon(Icons.folder_copy_outlined, size: 18),
                      label: Text(
                        folderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _buildPager(context)),
      ],
    );
  }

  Widget _buildPager(BuildContext context) {
    return ComicPager(
      key: Key("FAVOUR:$_folderId:$_sort:$_refreshGeneration"),
      hideStreamStatus: widget.embedded,
      longPressMenuItems: [
        ComicLongPressMenuItem(
          context.l10n.tr('移动到收藏夹', en: 'Move to favorites folder'),
          _moveFavoriteToFolder,
        ),
      ],
      onPage: (int page) async {
        final response = await methods.favorites(_folderId, page, _sort);
        if (mounted) {
          setState(() {
            _total = response.total;
            favData = response.folderList;
            _folderMap
              ..clear()
              ..addAll({
                0: context.l10n.all,
                for (final folder in response.folderList)
                  folder.fid: folder.name,
              });
          });
        }
        // count 会随尾页条数变化，分页器应保留首批条数作为容量。
        return InnerComicPage(
          total: response.total,
          list: response.list,
        );
      },
    );
  }
}
