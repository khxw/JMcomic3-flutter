import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/local_bookshelf.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

class BookshelfGroupManagementScreen extends StatefulWidget {
  const BookshelfGroupManagementScreen({super.key});

  @override
  State<BookshelfGroupManagementScreen> createState() =>
      _BookshelfGroupManagementScreenState();
}

class _BookshelfGroupManagementScreenState
    extends State<BookshelfGroupManagementScreen> {
  @override
  void initState() {
    super.initState();
    localBookshelfEvent.subscribe(_shelfChanged);
  }

  @override
  void dispose() {
    localBookshelfEvent.unsubscribe(_shelfChanged);
    super.dispose();
  }

  void _shelfChanged(_) {
    if (mounted) setState(() {});
  }

  Future<void> _createGroup() async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _GroupNameDialog(
        title: context.l10n.tr('新建分组', en: 'New group'),
        actionLabel: context.l10n.tr('创建', en: 'Create'),
        existingNames: localBookshelfGroupNames,
      ),
    );
    if (name == null || !mounted) return;
    await createLocalBookshelfGroup(name);
  }

  Future<void> _renameGroup(String oldName) async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _GroupNameDialog(
        title: context.l10n.tr('重命名分组', en: 'Rename group'),
        actionLabel: context.l10n.tr('保存', en: 'Save'),
        initialName: oldName,
        existingNames: localBookshelfGroupNames
            .where((name) => name != oldName)
            .toList(growable: false),
      ),
    );
    if (name == null || !mounted) return;
    await renameLocalBookshelfGroup(oldName, name);
  }

  Future<void> _deleteGroup(String name) async {
    final count = localBookshelfGroupCount(name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.tr('删除分组', en: 'Delete group')),
        content: Text(
          count == 0
              ? context.l10n.tr(
                  '确定删除“$name”吗？',
                  en: 'Delete “$name”?',
                )
              : context.l10n.tr(
                  '确定删除“$name”吗？其中的 $count 本漫画会保留在书架，并移到未分组。',
                  en: 'Delete “$name”? Its $count comics will stay in your bookshelf and become ungrouped.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.tr('取消', en: 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('bookshelf-group-delete-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.tr('删除', en: 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await deleteLocalBookshelfGroup(name);
  }

  @override
  Widget build(BuildContext context) {
    final groups = localBookshelfGroupNames;
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('bookshelf-group-management-page'),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.tr('分组管理', en: 'Manage groups')),
            Text(
              context.l10n.tr(
                '${groups.length} 个分组',
                en: '${groups.length} ${groups.length == 1 ? 'group' : 'groups'}',
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('bookshelf-group-create'),
        onPressed: _createGroup,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: Text(context.l10n.tr('新建分组', en: 'New group')),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: groups.isEmpty
            ? const _EmptyGroups(key: ValueKey('bookshelf-groups-empty'))
            : ListView.separated(
                key: ValueKey('bookshelf-groups-${groups.length}'),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
                itemCount: groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  final group = groups[index];
                  final count = localBookshelfGroupCount(group);
                  return RepaintBoundary(
                    child: Material(
                      key: ValueKey('bookshelf-group-item-$group'),
                      color: theme.colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: .5),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(
                          14,
                          5,
                          5,
                          5,
                        ),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: .11),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            count == 0
                                ? Icons.folder_open_outlined
                                : Icons.folder_rounded,
                            color: theme.colorScheme.primary,
                            size: 21,
                          ),
                        ),
                        title: Text(
                          group,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.tr(
                            count == 0 ? '空文件夹' : '$count 本漫画',
                            en: count == 0
                                ? 'Empty folder'
                                : '$count ${count == 1 ? 'comic' : 'comics'}',
                          ),
                        ),
                        trailing: PopupMenuButton<_GroupMenuAction>(
                          key: ValueKey('bookshelf-group-menu-$group'),
                          tooltip: context.l10n.tr(
                            '管理“$group”',
                            en: 'Manage “$group”',
                          ),
                          icon: const Icon(Icons.more_horiz_rounded),
                          onSelected: (action) {
                            switch (action) {
                              case _GroupMenuAction.rename:
                                _renameGroup(group);
                                break;
                              case _GroupMenuAction.delete:
                                _deleteGroup(group);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: _GroupMenuAction.rename,
                              key: ValueKey('bookshelf-group-rename-$group'),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.edit_outlined),
                                title: Text(
                                  context.l10n.tr(
                                    '重命名',
                                    en: 'Rename group',
                                  ),
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: _GroupMenuAction.delete,
                              key: ValueKey('bookshelf-group-delete-$group'),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.delete_outline_rounded,
                                  color: theme.colorScheme.error,
                                ),
                                title: Text(
                                  context.l10n.tr('删除分组', en: 'Delete group'),
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

enum _GroupMenuAction { rename, delete }

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups({super.key});

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
              size: 58,
              color: scheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              context.l10n.tr('还没有分组', en: 'No groups yet'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.tr(
                '创建分组后，可在漫画长按菜单中移动书架条目。',
                en: 'Create a group, then move bookshelf comics from their long-press menu.',
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

class _GroupNameDialog extends StatefulWidget {
  final String title;
  final String actionLabel;
  final String? initialName;
  final List<String> existingNames;

  const _GroupNameDialog({
    required this.title,
    required this.actionLabel,
    required this.existingNames,
    this.initialName,
  });

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName ?? "");

  String? get _errorText {
    final value = _controller.text.trim();
    if (value.isEmpty) return context.l10n.tr('请输入分组名称', en: 'Enter a name');
    if (widget.existingNames.any(
      (name) => name.trim().toLowerCase() == value.toLowerCase(),
    )) {
      return context.l10n.tr('该分组已存在', en: 'This group already exists');
    }
    return null;
  }

  void _submit() {
    if (_errorText != null) {
      setState(() {});
      return;
    }
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _errorText;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('bookshelf-group-name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 32,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: context.l10n.tr('分组名称', en: 'Group name'),
          errorText: error,
          prefixIcon: const Icon(Icons.folder_outlined),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.tr('取消', en: 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('bookshelf-group-save'),
          onPressed: error == null ? _submit : null,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
