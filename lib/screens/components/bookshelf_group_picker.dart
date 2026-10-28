import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/local_bookshelf.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

typedef BookshelfGroupPick = ({String? group, bool createNew});

Future<BookshelfGroupPick?> showBookshelfGroupPicker(
  BuildContext context, {
  required List<String> groups,
  String? selectedGroup,
  String? comicName,
}) {
  return showModalBottomSheet<BookshelfGroupPick>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _BookshelfGroupPickerSheet(
      groups: groups,
      selectedGroup: selectedGroup,
      comicName: comicName,
    ),
  );
}

Future<String?> showBookshelfGroupNameDialog(
  BuildContext context, {
  required List<String> existingNames,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _BookshelfGroupNameDialog(existingNames: existingNames),
  );
}

class _BookshelfGroupPickerSheet extends StatelessWidget {
  final List<String> groups;
  final String? selectedGroup;
  final String? comicName;

  const _BookshelfGroupPickerSheet({
    required this.groups,
    required this.selectedGroup,
    required this.comicName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sortedGroups = List<String>.of(groups)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Container(
      key: const ValueKey('bookshelf-group-picker'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .72,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .45)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.create_new_folder_outlined,
                    color: scheme.primary,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.tr('加入分组', en: 'Add to group'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        comicName?.trim().isNotEmpty == true
                            ? comicName!.trim()
                            : context.l10n.tr(
                                '选择漫画要加入的书架分组',
                                en: 'Choose a bookshelf group',
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
                IconButton(
                  key: const ValueKey('bookshelf-group-picker-close'),
                  tooltip: context.l10n.tr('关闭', en: 'Close'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Divider(
              height: 1, color: scheme.outlineVariant.withValues(alpha: .5)),
          if (sortedGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Column(
                children: [
                  Icon(
                    Icons.folder_copy_outlined,
                    size: 44,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.tr('还没有书架分组', en: 'No bookshelf groups yet'),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.tr(
                      '先新建一个分组，再将漫画加入其中。',
                      en: 'Create a group before adding this comic to it.',
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                itemCount: sortedGroups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  final group = sortedGroups[index];
                  final selected = group == selectedGroup;
                  final count = localBookshelfGroupCount(group);
                  return Material(
                    key: ValueKey('bookshelf-group-choice-$group'),
                    color: selected
                        ? scheme.primary.withValues(alpha: .13)
                        : scheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(
                        color: selected
                            ? scheme.primary.withValues(alpha: .48)
                            : scheme.outlineVariant.withValues(alpha: .55),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(
                        (group: group, createNew: false),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              count == 0
                                  ? Icons.folder_open_outlined
                                  : Icons.folder_rounded,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    group,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    context.l10n.tr(
                                      '$count 本漫画',
                                      en: '$count ${count == 1 ? 'comic' : 'comics'}',
                                    ),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              Icon(
                                Icons.check_circle_rounded,
                                color: scheme.primary,
                                size: 20,
                              )
                            else
                              Icon(
                                Icons.chevron_right_rounded,
                                color: scheme.onSurfaceVariant,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: FilledButton.icon(
              key: const ValueKey('bookshelf-group-picker-create'),
              onPressed: () => Navigator.of(context).pop(
                (group: null, createNew: true),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.l10n.tr('新建分组', en: 'New group')),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookshelfGroupNameDialog extends StatefulWidget {
  final List<String> existingNames;

  const _BookshelfGroupNameDialog({required this.existingNames});

  @override
  State<_BookshelfGroupNameDialog> createState() =>
      _BookshelfGroupNameDialogState();
}

class _BookshelfGroupNameDialogState extends State<_BookshelfGroupNameDialog> {
  final TextEditingController _controller = TextEditingController();

  String? get _errorText {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      return context.l10n.tr('请输入分组名称', en: 'Enter a group name');
    }
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
    Navigator.of(context).pop(_controller.text.trim());
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
      key: const ValueKey('bookshelf-add-group-dialog'),
      title: Text(context.l10n.tr('新建分组', en: 'New group')),
      content: TextField(
        key: const ValueKey('bookshelf-add-group-name-field'),
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
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.tr('取消', en: 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('bookshelf-add-group-save'),
          onPressed: error == null ? _submit : null,
          child: Text(context.l10n.tr('创建并加入', en: 'Create and add')),
        ),
      ],
    );
  }
}
