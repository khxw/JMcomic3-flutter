import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_pager.dart';

import 'components/app_back_button.dart';
import 'components/right_click_pop.dart';

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

  String _sort = "mr";
  var _refreshGeneration = 0;

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
    final sortNameMap = _sortNameMap(context);
    return Column(
      key: const ValueKey('bookshelf-online-content'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _folderMap[_folderId] ?? context.l10n.all,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              IconButton(
                key: const ValueKey('favorites-sort'),
                onPressed: _chooseSort,
                tooltip:
                    "${context.l10n.chooseSort}: ${sortNameMap[_sort] ?? ""}",
                icon: const Icon(Icons.sort_rounded, size: 21),
              ),
              IconButton(
                key: const ValueKey('favorites-folder'),
                onPressed: _chooseFolder,
                tooltip:
                    "${context.l10n.chooseFolder}: ${_folderMap[_folderId] ?? context.l10n.all}",
                icon: const Icon(Icons.folder_copy_outlined, size: 21),
              ),
              IconButton(
                key: const ValueKey('favorites-refresh'),
                onPressed: () {
                  setState(() => _refreshGeneration++);
                },
                tooltip: context.l10n.tr('刷新收藏', en: 'Refresh favorites'),
                icon: const Icon(Icons.refresh_rounded, size: 21),
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
      onPage: (int page) async {
        final response = await methods.favorites(_folderId, page, _sort);
        if (mounted) {
          setState(() {
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
