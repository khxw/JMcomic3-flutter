import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/local_bookshelf.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _backupFormat = 'jmcomic3-offline-bookshelf';
const _backupVersion = 1;
const _maxBackupBytes = 5 * 1024 * 1024;

class OfflineBookshelfBackupData {
  final List<LocalBookshelfItem> items;
  final List<String> groups;

  const OfflineBookshelfBackupData({
    required this.items,
    required this.groups,
  });

  factory OfflineBookshelfBackupData.parse(String raw) {
    final decoded = jsonDecode(raw);
    final items = <LocalBookshelfItem>[];
    final groups = <String>[];
    if (decoded is List) {
      for (final entry in decoded.whereType<Map>()) {
        final item = LocalBookshelfItem.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (item.comic.id > 0) items.add(item);
      }
      return OfflineBookshelfBackupData(items: items, groups: groups);
    }
    if (decoded is! Map ||
        decoded['format'] != _backupFormat ||
        (decoded['version'] is num &&
            (decoded['version'] as num).toInt() > _backupVersion)) {
      throw const FormatException('Unsupported bookshelf backup');
    }
    final rawItems = decoded['items'];
    if (rawItems is List) {
      for (final entry in rawItems.whereType<Map>()) {
        final item = LocalBookshelfItem.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (item.comic.id > 0) items.add(item);
      }
    }
    final rawGroups = decoded['groups'];
    if (rawGroups is List) {
      for (final value in rawGroups) {
        final group = '$value'.trim();
        if (group.isNotEmpty) groups.add(group);
      }
    }
    for (final item in items) {
      if (item.group.trim().isNotEmpty) groups.add(item.group.trim());
    }
    return OfflineBookshelfBackupData(items: items, groups: groups);
  }
}

class OfflineBookshelfImportResult {
  final int added;
  final int skipped;
  final int groupsAdded;

  const OfflineBookshelfImportResult({
    required this.added,
    required this.skipped,
    required this.groupsAdded,
  });
}

Future<String> encodeOfflineBookshelfBackup() async {
  await loadLocalBookshelf();
  return const JsonEncoder.withIndent('  ').convert({
    'format': _backupFormat,
    'version': _backupVersion,
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'groups': localBookshelfGroupNames,
    'items': localBookshelfItems
        .map((item) => item.toJson())
        .toList(growable: false),
  });
}

Future<OfflineBookshelfImportResult> importOfflineBookshelfBackup(
  OfflineBookshelfBackupData backup,
) async {
  await loadLocalBookshelf();
  var added = 0;
  var skipped = 0;
  var updated = false;
  final existingIds = {
    for (final item in localBookshelfItems) item.comic.id,
  };
  for (final item in backup.items) {
    if (existingIds.contains(item.comic.id)) {
      skipped++;
      final index = localBookshelfItems.indexWhere(
        (current) => current.comic.id == item.comic.id,
      );
      if (index >= 0 &&
          localBookshelfItems[index].group.trim().isEmpty &&
          item.group.trim().isNotEmpty) {
        localBookshelfItems[index] =
            localBookshelfItems[index].copyWith(group: item.group);
        updated = true;
      }
      continue;
    }
    localBookshelfItems.add(item);
    existingIds.add(item.comic.id);
    added++;
  }
  final groupsBefore = localBookshelfGroups.length;
  for (final group in backup.groups) {
    await createLocalBookshelfGroup(group);
  }
  if (added > 0 || updated || groupsBefore != localBookshelfGroups.length) {
    await saveLocalBookshelf();
  }
  return OfflineBookshelfImportResult(
    added: added,
    skipped: skipped,
    groupsAdded: localBookshelfGroups.length - groupsBefore,
  );
}

Future<void> exportOfflineBookshelfBackup(BuildContext context) async {
  try {
    final content = await encodeOfflineBookshelfBackup();
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final fileName =
        'JMComic3-bookshelf-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: context.l10n.tr('导出离线书架备份'),
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (path == null || !context.mounted) return;
    defaultToast(
      context,
      context.l10n.tr('离线书架备份已导出'),
    );
  } catch (error) {
    if (context.mounted) {
      defaultToast(
        context,
        context.l10n.tr('导出离线书架备份失败：$error'),
      );
    }
  }
}

Future<void> importOfflineBookshelfBackupFromFile(
  BuildContext context,
) async {
  try {
    final selected = await FilePicker.platform.pickFiles(
      dialogTitle: context.l10n.tr('导入离线书架备份'),
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      withData: true,
    );
    if (selected == null || selected.files.isEmpty || !context.mounted) return;
    final file = selected.files.single;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      throw const FormatException('Unable to read backup file');
    }
    if (bytes.length > _maxBackupBytes) {
      throw const FormatException('Backup file is too large');
    }
    final backup = OfflineBookshelfBackupData.parse(utf8.decode(bytes));
    if (!context.mounted) return;
    final confirmed = await confirmDialog(
      context,
      context.l10n.tr('导入离线书架备份'),
      context.l10n.tr(
        '将合并 ${backup.items.length} 本漫画和 ${backup.groups.length} 个分组，重复漫画会自动跳过。',
      ),
    );
    if (!confirmed || !context.mounted) return;
    final result = await importOfflineBookshelfBackup(backup);
    if (!context.mounted) return;
    defaultToast(
      context,
      context.l10n.tr(
        '导入完成：新增 ${result.added} 本，跳过 ${result.skipped} 本',
      ),
    );
  } catch (error) {
    if (context.mounted) {
      defaultToast(
        context,
        context.l10n.tr('导入离线书架备份失败：$error'),
      );
    }
  }
}
