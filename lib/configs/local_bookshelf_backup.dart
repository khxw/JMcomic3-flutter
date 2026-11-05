import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/local_bookshelf.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _backupFormat = 'jmcomic3-offline-bookshelf';
const _backupVersion = 2;
const _maxBackupBytes = 32 * 1024 * 1024;

class OfflineReadingProgress {
  final int comicId;
  final int chapterId;
  final int page;
  final int viewedAt;

  const OfflineReadingProgress({
    required this.comicId,
    required this.chapterId,
    required this.page,
    required this.viewedAt,
  });

  factory OfflineReadingProgress.fromJson(Map<String, dynamic> json) {
    return OfflineReadingProgress(
      comicId: _toInt(json['comic_id']),
      chapterId: _toInt(json['chapter_id']),
      page: _toInt(json['page']),
      viewedAt: _toInt(json['viewed_at']),
    );
  }

  bool get isValid => comicId > 0 && chapterId > 0 && page >= 0;

  Map<String, dynamic> toJson() => {
        'comic_id': comicId,
        'chapter_id': chapterId,
        'page': page,
        'viewed_at': viewedAt,
      };

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

class OfflineBookshelfBackupData {
  final List<LocalBookshelfItem> items;
  final List<String> groups;
  final List<OfflineReadingProgress> readingProgress;

  const OfflineBookshelfBackupData({
    required this.items,
    required this.groups,
    this.readingProgress = const [],
  });

  factory OfflineBookshelfBackupData.parse(String raw) {
    final decoded = jsonDecode(raw);
    final items = <LocalBookshelfItem>[];
    final groups = <String>[];
    final readingProgress = <OfflineReadingProgress>[];
    if (decoded is List) {
      for (final entry in decoded.whereType<Map>()) {
        final item = LocalBookshelfItem.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (item.comic.id > 0 &&
            !items.any((existing) => existing.comic.id == item.comic.id)) {
          items.add(item);
        }
      }
      return OfflineBookshelfBackupData(
        items: items,
        groups: groups,
        readingProgress: readingProgress,
      );
    }
    if (decoded is! Map || decoded['format'] != _backupFormat) {
      throw const FormatException('Unsupported bookshelf backup');
    }
    final version = OfflineReadingProgress._toInt(decoded['version']);
    if (version > _backupVersion) {
      throw const FormatException('Unsupported bookshelf backup version');
    }
    final rawItems = decoded['items'];
    if (rawItems is List) {
      for (final entry in rawItems.whereType<Map>()) {
        final item = LocalBookshelfItem.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (item.comic.id > 0 &&
            !items.any((existing) => existing.comic.id == item.comic.id)) {
          items.add(item);
        }
      }
    }
    final rawGroups = decoded['groups'];
    if (rawGroups is List) {
      for (final value in rawGroups) {
        final group = '$value'.trim();
        if (group.isNotEmpty &&
            !groups.any(
              (existing) => existing.toLowerCase() == group.toLowerCase(),
            )) {
          groups.add(group);
        }
      }
    }
    for (final item in items) {
      final group = item.group.trim();
      if (group.isNotEmpty &&
          !groups.any(
            (existing) => existing.toLowerCase() == group.toLowerCase(),
          )) {
        groups.add(group);
      }
    }
    final rawProgress = decoded['reading_progress'];
    if (rawProgress is List) {
      for (final entry in rawProgress.whereType<Map>()) {
        final progress = OfflineReadingProgress.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (progress.isValid) readingProgress.add(progress);
      }
    }
    return OfflineBookshelfBackupData(
      items: items,
      groups: groups,
      readingProgress: readingProgress,
    );
  }
}

class OfflineBookshelfImportResult {
  final int added;
  final int skipped;
  final int groupsAdded;
  final int progressRestored;
  final int progressFailed;

  const OfflineBookshelfImportResult({
    required this.added,
    required this.skipped,
    required this.groupsAdded,
    required this.progressRestored,
    this.progressFailed = 0,
  });
}

Future<String> encodeOfflineBookshelfBackup() async {
  await loadLocalBookshelf();
  final readingProgress = <OfflineReadingProgress>[];
  const batchSize = 8;
  for (var offset = 0;
      offset < localBookshelfItems.length;
      offset += batchSize) {
    final end =
        (offset + batchSize).clamp(0, localBookshelfItems.length).toInt();
    final batch = localBookshelfItems.sublist(offset, end);
    final logs = await Future.wait(
      batch.map((item) async {
        try {
          return await methods.findViewLog(item.comic.id);
        } catch (_) {
          return null;
        }
      }),
    );
    for (var index = 0; index < logs.length; index++) {
      final log = logs[index];
      if (log == null || log.lastViewChapterId <= 0 || log.lastViewPage < 0) {
        continue;
      }
      readingProgress.add(OfflineReadingProgress(
        comicId: batch[index].comic.id,
        chapterId: log.lastViewChapterId,
        page: log.lastViewPage,
        viewedAt: log.lastViewTime,
      ));
    }
  }
  return const JsonEncoder.withIndent('  ').convert({
    'format': _backupFormat,
    'version': _backupVersion,
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'groups': localBookshelfGroupNames,
    'items': localBookshelfItems
        .map((item) => item.toJson())
        .toList(growable: false),
    'reading_progress': readingProgress
        .map((progress) => progress.toJson())
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
  var progressRestored = 0;
  var progressFailed = 0;
  for (final progress in backup.readingProgress) {
    if (!existingIds.contains(progress.comicId)) continue;
    final current = await methods.findViewLog(progress.comicId);
    final shouldRestore = current == null ||
        current.lastViewChapterId <= 0 ||
        progress.viewedAt <= 0 ||
        progress.viewedAt > current.lastViewTime;
    if (!shouldRestore) continue;
    try {
      await methods.updateViewLog(
        progress.comicId,
        progress.chapterId,
        progress.page,
        viewedAt: progress.viewedAt,
      );
      progressRestored++;
    } catch (_) {
      progressFailed++;
    }
  }
  return OfflineBookshelfImportResult(
    added: added,
    skipped: skipped,
    groupsAdded: localBookshelfGroups.length - groupsBefore,
    progressRestored: progressRestored,
    progressFailed: progressFailed,
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
    final bytes = Uint8List.fromList(utf8.encode(content));
    if (Platform.isAndroid) {
      final uri = await methods.saveTextDocument(
        fileName: fileName,
        content: content,
        mimeType: 'application/json',
      );
      if (uri == null || !context.mounted) return;
      if (context.mounted) {
        defaultToast(
          context,
          context.l10n.tr(
            '离线书架和阅读进度备份已导出',
            en: 'Offline bookshelf and reading progress exported',
          ),
        );
      }
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: context.l10n.tr('导出离线书架备份'),
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
    );
    if (path == null || !context.mounted) return;
    if (!path.startsWith('content://')) {
      final file = File(path);
      if (!await file.exists() || await file.length() == 0) {
        await file.writeAsBytes(bytes, flush: true);
      }
    }
    defaultToast(
      context,
      context.l10n.tr(
        '离线书架和阅读进度备份已导出',
        en: 'Offline bookshelf and reading progress exported',
      ),
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
    late final String text;
    if (Platform.isAndroid) {
      final selected = await methods.openTextDocument(
        mimeType: 'application/json',
        maxBytes: _maxBackupBytes,
      );
      if (selected == null || !context.mounted) return;
      text = selected;
    } else {
      final selected = await FilePicker.platform.pickFiles(
        dialogTitle: context.l10n.tr('导入离线书架备份'),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
        withData: true,
      );
      if (selected == null || selected.files.isEmpty || !context.mounted) {
        return;
      }
      final file = selected.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) {
        throw const FormatException('Unable to read backup file');
      }
      if (bytes.length > _maxBackupBytes) {
        throw const FormatException('Backup file is too large');
      }
      text = utf8.decode(bytes);
    }
    final backup = OfflineBookshelfBackupData.parse(
      text.replaceFirst(RegExp(r'^\uFEFF'), ''),
    );
    if (!context.mounted) return;
    final confirmed = await confirmDialog(
      context,
      context.l10n.tr('导入离线书架备份'),
      context.l10n.tr(
        '将合并 ${backup.items.length} 本漫画、${backup.groups.length} 个分组和 '
        '${backup.readingProgress.length} 条阅读进度，重复漫画会自动跳过。',
        en: 'Merge ${backup.items.length} comics, ${backup.groups.length} groups '
            'and ${backup.readingProgress.length} reading positions? '
            'Duplicate comics will be skipped.',
      ),
    );
    if (!confirmed || !context.mounted) return;
    final result = await importOfflineBookshelfBackup(backup);
    if (!context.mounted) return;
    defaultToast(
      context,
      context.l10n.tr(
        '导入完成：新增 ${result.added} 本，跳过 ${result.skipped} 本，'
        '恢复 ${result.progressRestored} 条阅读进度'
        '${result.progressFailed > 0 ? '，${result.progressFailed} 条恢复失败' : ''}',
        en: 'Import complete: ${result.added} added, ${result.skipped} skipped, '
            '${result.progressRestored} reading positions restored'
            '${result.progressFailed > 0 ? ', ${result.progressFailed} failed' : ''}',
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
