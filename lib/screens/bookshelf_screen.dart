import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/local_bookshelf.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/bookshelf_group_management_screen.dart';
import 'package:jmcomic3/screens/bookshelf_group_screen.dart';
import 'package:jmcomic3/screens/components/content_loading.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({Key? key}) : super(key: key);

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
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

  void _shelfChanged(_) {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool force = false}) async {
    if (force && mounted) {
      setState(() => _loading = true);
    }
    await loadLocalBookshelf(force: force);
    final savedSort = await methods.loadProperty("bookshelf_sort");
    if (!mounted) return;
    setState(() {
      if (_sortNames(context).containsKey(savedSort)) {
        _sort = savedSort;
      }
      _loading = false;
    });
  }

  Map<String, String> _sortNames(BuildContext context) => {
        _sortRecent: context.l10n.tr('最近加入', en: 'Recently added'),
        _sortTitle: context.l10n.tr('标题', en: 'Title'),
        _sortAuthor: context.l10n.tr('作者', en: 'Author'),
      };

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
  }

  Future<void> _openFolder(_ShelfFolder folder) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookshelfGroupScreen(
          title: folder.title,
          group: folder.group,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = localBookshelfGroupNames;
    final books = localBookshelfItems.length;
    return Scaffold(
      key: const ValueKey('compose-bookshelf-page'),
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 16,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Column(
            key: ValueKey('${groups.length}:$books:$_sort'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.navLibrary,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.3,
                    ),
              ),
              Text(
                context.l10n.tr(
                  '${groups.length} 个分组 · $books 本漫画',
                  en: '${groups.length} ${groups.length == 1 ? 'group' : 'groups'} · $books ${books == 1 ? 'comic' : 'comics'}',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<_ShelfMenuAction>(
            key: const ValueKey('bookshelf-options-menu'),
            tooltip: context.l10n.tr('书架菜单', en: 'Bookshelf menu'),
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (action) {
              switch (action) {
                case _ShelfMenuAction.manageGroups:
                  _manageGroups();
                  break;
                case _ShelfMenuAction.sort:
                  _chooseSort();
                  break;
                case _ShelfMenuAction.refresh:
                  _load(force: true);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _ShelfMenuAction.manageGroups,
                child: _ShelfMenuItem(
                  icon: Icons.create_new_folder_outlined,
                  title: context.l10n.tr('分组管理', en: 'Manage groups'),
                  subtitle: context.l10n.tr(
                    '新建、重命名或删除文件夹',
                    en: 'Create, rename or delete folders',
                  ),
                ),
              ),
              PopupMenuItem(
                value: _ShelfMenuAction.sort,
                child: _ShelfMenuItem(
                  icon: Icons.sort_rounded,
                  title: context.l10n.tr('排列', en: 'Sort'),
                  subtitle: _sortNames(context)[_sort] ?? '',
                ),
              ),
              PopupMenuItem(
                value: _ShelfMenuAction.refresh,
                child: _ShelfMenuItem(
                  icon: Icons.refresh_rounded,
                  title: context.l10n.tr('刷新书架', en: 'Refresh'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom,
        ),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const ContentLoading();
    }
    final folders = _folders(context);
    if (folders.isEmpty) {
      return _EmptyBookshelf(onCreateGroup: _manageGroups);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        int columns;
        if (scale > 1.35) {
          if (constraints.maxWidth >= 760) {
            columns = 3;
          } else if (constraints.maxWidth >= 360) {
            columns = 2;
          } else {
            columns = 1;
          }
        } else if (constraints.maxWidth >= 1000) {
          columns = 6;
        } else if (constraints.maxWidth >= 760) {
          columns = 5;
        } else if (constraints.maxWidth >= 560) {
          columns = 4;
        } else if (constraints.maxWidth >= 360) {
          columns = 3;
        } else if (constraints.maxWidth >= 300) {
          columns = 2;
        } else {
          columns = 1;
        }
        return GridView.builder(
          key: const ValueKey('bookshelf-folder-grid'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
          itemCount: folders.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: scale > 1.3 ? 170 : 128,
          ),
          itemBuilder: (context, index) {
            final folder = folders[index];
            return _ShelfFolderCard(
              folder: folder,
              onTap: () => _openFolder(folder),
            );
          },
        );
      },
    );
  }

  List<_ShelfFolder> _folders(BuildContext context) {
    final groups = localBookshelfGroupNames;
    final total = localBookshelfItems.length;
    final ungrouped = localBookshelfGroupCount("");
    final folders = <_ShelfFolder>[];
    if (total > 0) {
      folders.add(
        _ShelfFolder(
          title: context.l10n.all,
          group: null,
          count: total,
          kind: _ShelfFolderKind.all,
        ),
      );
    }
    for (final group in groups) {
      folders.add(
        _ShelfFolder(
          title: group,
          group: group,
          count: localBookshelfGroupCount(group),
          kind: _ShelfFolderKind.group,
        ),
      );
    }
    if (groups.isNotEmpty && ungrouped > 0) {
      folders.add(
        _ShelfFolder(
          title: context.l10n.tr('未分组', en: 'Ungrouped'),
          group: "",
          count: ungrouped,
          kind: _ShelfFolderKind.ungrouped,
        ),
      );
    }
    return folders;
  }
}

enum _ShelfMenuAction { manageGroups, sort, refresh }

enum _ShelfFolderKind { all, group, ungrouped }

class _ShelfFolder {
  final String title;
  final String? group;
  final int count;
  final _ShelfFolderKind kind;

  const _ShelfFolder({
    required this.title,
    required this.group,
    required this.count,
    required this.kind,
  });

  String get key {
    if (kind == _ShelfFolderKind.all) return 'all';
    if (kind == _ShelfFolderKind.ungrouped) return 'ungrouped';
    return group ?? 'all';
  }
}

class _ShelfFolderCard extends StatefulWidget {
  final _ShelfFolder folder;
  final VoidCallback onTap;

  const _ShelfFolderCard({
    required this.folder,
    required this.onTap,
  });

  @override
  State<_ShelfFolderCard> createState() => _ShelfFolderCardState();
}

class _ShelfFolderCardState extends State<_ShelfFolderCard> {
  static const _palette = <Color>[
    Color(0xFF128C8A),
    Color(0xFF5968E8),
    Color(0xFFC0448C),
    Color(0xFFE0782B),
    Color(0xFF3F7D45),
    Color(0xFF7455C8),
    Color(0xFF287BB5),
  ];

  bool _pressed = false;

  Color _groupAccent(ColorScheme scheme) {
    if (widget.folder.kind == _ShelfFolderKind.all) return scheme.primary;
    if (widget.folder.kind == _ShelfFolderKind.ungrouped) {
      return scheme.onSurfaceVariant;
    }
    final seed = widget.folder.title.codeUnits.fold<int>(
      0,
      (value, codeUnit) => (value * 31 + codeUnit) % 2147483647,
    );
    return _palette[seed % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final folder = widget.folder;
    final accent = _groupAccent(scheme);
    final empty = folder.count == 0;
    final countLabel = empty
        ? context.l10n.tr('空文件夹', en: 'Empty folder')
        : context.l10n.tr(
            '${folder.count} 本漫画',
            en: '${folder.count} ${folder.count == 1 ? 'comic' : 'comics'}',
          );
    final background = folder.kind == _ShelfFolderKind.all
        ? Color.alphaBlend(
            accent.withValues(alpha: .1),
            scheme.surfaceContainerLow,
          )
        : scheme.surfaceContainerLow;
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: '${folder.title}，$countLabel',
        hint: context.l10n.tr('打开文件夹', en: 'Open folder'),
        child: ExcludeSemantics(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedScale(
              scale: _pressed ? .985 : 1,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOutCubic,
              child: Material(
                key: ValueKey('bookshelf-folder-${folder.key}'),
                color: background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: accent.withValues(alpha: .16),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: widget.onTap,
                  onHighlightChanged: (pressed) {
                    if (_pressed != pressed) {
                      setState(() => _pressed = pressed);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(
                                folder.kind == _ShelfFolderKind.all
                                    ? Icons.collections_bookmark_rounded
                                    : empty
                                        ? Icons.folder_open_outlined
                                        : Icons.folder_rounded,
                                color: accent,
                                size: 19,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              empty
                                  ? context.l10n.tr('空', en: 'Empty')
                                  : context.l10n.tr(
                                      '${folder.count} 本',
                                      en: '${folder.count}',
                                    ),
                              maxLines: 1,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(
                                folder.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 19,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBookshelf extends StatelessWidget {
  final VoidCallback onCreateGroup;

  const _EmptyBookshelf({required this.onCreateGroup});

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
              Icons.folder_copy_outlined,
              size: 50,
              color: scheme.primary,
            ),
            const SizedBox(height: 13),
            Text(
              context.l10n.tr(
                '书架还是空的',
                en: 'Your bookshelf is empty',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.tr(
                '先创建一个文件夹分组，再加入漫画。',
                en: 'Create a folder group first, then add comics to it.',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('bookshelf-empty-create-group'),
              onPressed: onCreateGroup,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(
                context.l10n.tr('新建分组', en: 'New group'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShelfMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _ShelfMenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
