import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/local_bookshelf.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/bookshelf_group_management_screen.dart';
import 'package:jmcomic3/screens/components/comic_list.dart';
import 'package:jmcomic3/screens/components/content_loading.dart';
import 'package:jmcomic3/screens/components/types.dart';

import 'components/app_back_button.dart';

class BookshelfGroupScreen extends StatefulWidget {
  final String title;
  final String? group;

  const BookshelfGroupScreen({
    super.key,
    required this.title,
    required this.group,
  });

  @override
  State<BookshelfGroupScreen> createState() => _BookshelfGroupScreenState();
}

class _BookshelfGroupScreenState extends State<BookshelfGroupScreen> {
  static const _sortRecent = "recent";
  static const _sortTitle = "title";
  static const _sortAuthor = "author";

  bool _loading = true;
  String _sort = _sortRecent;

  @override
  void initState() {
    super.initState();
    localBookshelfEvent.subscribe(_shelfChanged);
    _load();
  }

  @override
  void dispose() {
    localBookshelfEvent.unsubscribe(_shelfChanged);
    super.dispose();
  }

  Future<void> _load() async {
    await loadLocalBookshelf();
    final savedSort = await methods.loadProperty("bookshelf_sort");
    if (!mounted) return;
    setState(() {
      if (_sortNames(context).containsKey(savedSort)) {
        _sort = savedSort;
      }
      _loading = false;
    });
  }

  void _shelfChanged(_) {
    if (!mounted) return;
    final group = widget.group;
    if (group != null &&
        group.isNotEmpty &&
        !localBookshelfGroupNames.contains(group)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.maybePop(context);
      });
      return;
    }
    setState(() {});
  }

  Map<String, String> _sortNames(BuildContext context) => {
        _sortRecent: context.l10n.tr('最近加入', en: 'Recently added'),
        _sortTitle: context.l10n.tr('标题', en: 'Title'),
        _sortAuthor: context.l10n.tr('作者', en: 'Author'),
      };

  List<LocalBookshelfItem> get _items {
    final items = localBookshelfItems.where((item) {
      final group = widget.group;
      return group == null || item.group == group;
    }).toList();
    switch (_sort) {
      case _sortTitle:
        items.sort(
          (a, b) => a.comic.name.toLowerCase().compareTo(
                b.comic.name.toLowerCase(),
              ),
        );
        break;
      case _sortAuthor:
        items.sort(
          (a, b) => a.comic.author.toLowerCase().compareTo(
                b.comic.author.toLowerCase(),
              ),
        );
        break;
      case _sortRecent:
      default:
        items.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
    }
    return items;
  }

  Future<void> _chooseSort() async {
    final names = _sortNames(context);
    final selected = await chooseMapDialog<String>(
      context,
      values: names.map((key, value) => MapEntry(value, key)),
      title: context.l10n.chooseSort,
    );
    if (selected == null || !mounted) return;
    setState(() => _sort = selected);
    await methods.saveProperty("bookshelf_sort", selected);
  }

  Future<void> _manageGroups() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const BookshelfGroupManagementScreen(),
      ),
    );
    if (!mounted) return;
    final group = widget.group;
    if (group != null &&
        group.isNotEmpty &&
        !localBookshelfGroupNames.contains(group)) {
      Navigator.maybePop(context);
    }
  }

  Future<void> _moveToGroup(ComicBasic comic) async {
    final values = <String, String>{
      context.l10n.tr('未分组', en: 'Ungrouped'): "",
      for (final group in localBookshelfGroupNames) group: group,
    };
    final selected = await chooseMapDialog<String>(
      context,
      values: values,
      title: context.l10n.tr('移动到分组', en: 'Move to group'),
    );
    if (selected == null || !mounted) return;
    await moveLocalBookshelfItem(comic.id, selected);
    if (!mounted) return;
    defaultToast(
      context,
      context.l10n.tr('分组已更新', en: 'Group updated'),
    );
  }

  Future<void> _removeFromShelf(ComicBasic comic) async {
    await removeLocalBookshelfItem(comic.id);
    if (!mounted) return;
    defaultToast(
      context,
      context.l10n.tr('已从书架移除', en: 'Removed from bookshelf'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _items;
    return Scaffold(
      key: ValueKey('bookshelf-group-page-${widget.group ?? 'all'}'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: const AppBackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${items.length} ${context.l10n.tr('本漫画', en: 'comics')} · '
              '${_sortNames(context)[_sort]}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_GroupMenuAction>(
            key: const ValueKey('bookshelf-group-options-menu'),
            tooltip: context.l10n.tr('分组菜单', en: 'Group menu'),
            onSelected: (action) {
              switch (action) {
                case _GroupMenuAction.sort:
                  _chooseSort();
                  break;
                case _GroupMenuAction.manageGroups:
                  _manageGroups();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _GroupMenuAction.sort,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sort_rounded),
                  title: Text(context.l10n.tr('排列', en: 'Sort')),
                  subtitle: Text(_sortNames(context)[_sort] ?? ''),
                ),
              ),
              PopupMenuItem(
                value: _GroupMenuAction.manageGroups,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: Text(
                    context.l10n.tr('分组管理', en: 'Manage groups'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const ContentLoading()
          : items.isEmpty
              ? _EmptyFolder(title: widget.title)
              : ComicList(
                  key: ValueKey(
                    'GROUP_BOOKSHELF:${widget.group ?? 'all'}:$_sort:${items.length}',
                  ),
                  data: items.map((item) => item.comic).toList(growable: false),
                  longPressMenuItems: [
                    if (localBookshelfGroupNames.isNotEmpty)
                      ComicLongPressMenuItem(
                        context.l10n.tr('移动到分组', en: 'Move to group'),
                        _moveToGroup,
                      ),
                    ComicLongPressMenuItem(
                      context.l10n.tr('移出书架', en: 'Remove from bookshelf'),
                      _removeFromShelf,
                    ),
                  ],
                ),
    );
  }
}

enum _GroupMenuAction { sort, manageGroups }

class _EmptyFolder extends StatelessWidget {
  final String title;

  const _EmptyFolder({required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 52,
              color: scheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.tr(
                '“$title”里还没有漫画',
                en: 'No comics in “$title” yet',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.tr(
                '在书架中长按漫画并选择“移动到分组”。',
                en: 'Long-press a bookshelf comic and choose “Move to group”.',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
