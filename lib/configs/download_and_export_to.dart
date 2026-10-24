import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'string_property.dart';

const _directoryPropertyKey = "custom_download_directory_path";
String _currentDownloadDirectory = "";

Future<String?> initDownloadAndExportTo() async {
  await refreshCustomDownloadDirectory();
  return null;
}

Future<void> refreshCustomDownloadDirectory() async {
  var backendPath = "";
  var savedPath = "";
  try {
    backendPath = normalizeDownloadDirectoryPath(
      await methods.getDownloadAndExportTo(),
    );
  } catch (_) {}
  try {
    savedPath = normalizeDownloadDirectoryPath(
      await methods.loadProperty(_directoryPropertyKey),
    );
  } catch (_) {}
  if (backendPath.isNotEmpty) {
    _currentDownloadDirectory = backendPath;
    if (savedPath != backendPath) {
      try {
        await methods.saveProperty(_directoryPropertyKey, backendPath);
      } catch (_) {}
    }
    return;
  }
  if (savedPath.isNotEmpty) {
    _currentDownloadDirectory = savedPath;
    try {
      await methods.setDownloadAndExportTo(savedPath);
    } catch (_) {}
    return;
  }
  _currentDownloadDirectory = "";
}

String get currentDownloadAndExportTo => _currentDownloadDirectory;

bool get hasCustomDownloadDirectory => _currentDownloadDirectory.isNotEmpty;

String currentDownloadAndExportToName() {
  return hasCustomDownloadDirectory ? _currentDownloadDirectory : "App storage";
}

String normalizeDownloadDirectoryPath(Object? raw) {
  return parseStringPropertyValue("${raw ?? ""}", trim: true);
}

Future<bool> setCustomDownloadDirectory(String path) async {
  final normalized = normalizeDownloadDirectoryPath(path);
  _currentDownloadDirectory = normalized;
  try {
    await methods.saveProperty(_directoryPropertyKey, normalized);
  } catch (_) {}
  try {
    await methods.setDownloadAndExportTo(normalized);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> chooseCustomDownloadDirectory(BuildContext context) async {
  String? selected;
  try {
    selected = Platform.isAndroid
        ? await methods.androidPickDownloadDirectory()
        : await chooseFolder(context);
  } on PlatformException catch (error) {
    if (context.mounted) {
      defaultToast(
        context,
        error.message ??
            context.l10n.tr(
              "无法读取该目录，请选择本机存储中的文件夹",
              en: "Could not access that folder. Choose a folder on local storage.",
            ),
      );
    }
    return false;
  } catch (_) {
    if (context.mounted) {
      defaultToast(
        context,
        context.l10n.tr(
          "无法读取该目录，请选择本机存储中的文件夹",
          en: "Could not access that folder. Choose a folder on local storage.",
        ),
      );
    }
    return false;
  }
  if (selected == null) return false;
  final normalized = normalizeDownloadDirectoryPath(selected);
  if (normalized.isEmpty) return false;

  if (Platform.isAndroid) {
    var writable = await methods.androidDirectoryWritable(normalized);
    if (!writable) {
      final granted = await androidMangeStorageRequest();
      if (!granted) {
        if (context.mounted) {
          await _showStoragePermissionHelp(context);
        }
        return false;
      }
      writable = await methods.androidDirectoryWritable(normalized);
      if (!writable) {
        if (context.mounted) {
          defaultToast(
            context,
            context.l10n.tr(
              "该目录仍不可写，请选择 Download 下的子文件夹",
              en: "The folder is still not writable. Choose a subfolder under Download.",
            ),
          );
        }
        return false;
      }
    }
  }

  final synced = await setCustomDownloadDirectory(normalized);
  if (context.mounted) {
    defaultToast(
      context,
      synced
          ? context.l10n.tr("下载目录已更新", en: "Download directory updated")
          : context.l10n.tr(
              "路径已记录，后端同步将在下次启动时重试",
              en: "Path saved; backend sync will retry on next launch",
            ),
    );
  }
  return true;
}

Future<bool> _ensureDownloadStoragePermission(BuildContext context) async {
  if (!Platform.isAndroid) return true;
  final granted = await androidMangeStorageRequest();
  if (granted) return true;
  if (context.mounted) {
    await _showStoragePermissionHelp(context);
  }
  return false;
}

Future<void> _showStoragePermissionHelp(BuildContext context) async {
  final openSettings = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        context.l10n.tr("需要文件访问权限", en: "File access permission"),
      ),
      content: Text(
        context.l10n.tr(
          "Android 11 及以上需要允许“所有文件访问”，才能直接写入系统公共目录。"
          "授权后请返回并重新选择文件夹。",
          en: "Android 11 and newer requires All files access to write directly "
              "to public storage. Grant it, then return and choose the folder again.",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(context.l10n.tr("取消", en: "Cancel")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(context.l10n.tr("打开权限设置", en: "Open settings")),
        ),
      ],
    ),
  );
  if (openSettings == true) {
    await openAppSettings();
  }
}

Future<bool> clearCustomDownloadDirectory(BuildContext context) async {
  final synced = await setCustomDownloadDirectory("");
  if (context.mounted) {
    defaultToast(
      context,
      synced
          ? context.l10n.tr(
              "已恢复应用内部存储",
              en: "Using app storage again",
            )
          : context.l10n.tr(
              "已恢复本地显示，后端同步将在下次启动时重试",
              en: "Local setting cleared; backend sync will retry on next launch",
            ),
    );
  }
  return true;
}

Future<bool> editCustomDownloadDirectory(BuildContext context) async {
  final choose = context.l10n.tr("选择文件夹", en: "Choose folder");
  final manual = context.l10n.tr("手动输入路径", en: "Enter path manually");
  final useDefault = context.l10n.tr("恢复应用内部存储", en: "Use app storage");
  final selected = await chooseListDialog(
    context,
    values: [
      choose,
      manual,
      if (hasCustomDownloadDirectory) useDefault,
    ],
    title: context.l10n.tr("自定义下载目录", en: "Custom download directory"),
  );
  if (selected == null) return false;
  if (selected == choose) {
    return chooseCustomDownloadDirectory(context);
  }
  if (selected == manual) {
    final value = await displayTextInputDialog(
      context,
      title: context.l10n.tr("下载目录路径", en: "Download directory path"),
      hint: "/storage/emulated/0/Download/JMComic3Mod",
      src: _currentDownloadDirectory,
    );
    final normalized = normalizeDownloadDirectoryPath(value);
    if (normalized.isEmpty) return false;
    if (Platform.isAndroid) {
      if (!await _ensureDownloadStoragePermission(context)) {
        return false;
      }
      var writable = await methods.androidDirectoryWritable(normalized);
      if (!writable) {
        final granted = await androidMangeStorageRequest();
        if (!granted) {
          if (context.mounted) await _showStoragePermissionHelp(context);
          return false;
        }
        writable = await methods.androidDirectoryWritable(normalized);
        if (!writable) {
          if (context.mounted) {
            defaultToast(
              context,
              context.l10n.tr(
                "该目录不可写，请检查路径或权限",
                en: "The folder is not writable. Check the path or permission.",
              ),
            );
          }
          return false;
        }
      }
    }
    final synced = await setCustomDownloadDirectory(normalized);
    if (context.mounted) {
      defaultToast(
        context,
        synced
            ? context.l10n.tr("下载目录已更新", en: "Download directory updated")
            : context.l10n.tr(
                "路径已记录，后端同步将在下次启动时重试",
                en: "Path saved; backend sync will retry on next launch",
              ),
      );
    }
    return true;
  }
  if (selected == useDefault) {
    return clearCustomDownloadDirectory(context);
  }
  return false;
}

Widget downloadDirectorySetting({bool compact = false}) {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      final l10n = context.l10n;
      final custom = hasCustomDownloadDirectory;
      final directoryLabel = custom
          ? _currentDownloadDirectory
          : l10n.tr("应用内部存储", en: "App storage");
      final statusLabel =
          custom ? l10n.tr("已启用", en: "Custom") : l10n.tr("默认", en: "Default");
      final statusColor = custom
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant;

      final leading = Container(
        width: compact ? 34 : 38,
        height: compact ? 34 : 38,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(
          custom ? Icons.folder_rounded : Icons.folder_outlined,
          color: Theme.of(context).colorScheme.primary,
          size: compact ? 19 : 21,
        ),
      );
      final status = Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          statusLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
      Future<void> edit() async {
        if (await editCustomDownloadDirectory(context)) {
          setState(() {});
        }
      }

      if (compact) {
        return ListTile(
          key: const ValueKey('download-directory-setting'),
          contentPadding: const EdgeInsets.fromLTRB(12, 3, 8, 3),
          visualDensity: VisualDensity.compact,
          leading: leading,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.tr("自定义下载目录", en: "Custom download directory"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              status,
            ],
          ),
          subtitle: Row(
            children: [
              Text(
                l10n.tr("当前目录", en: "Current"),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  directoryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          trailing: IconButton(
            tooltip: l10n.tr("更改下载目录", en: "Change download directory"),
            onPressed: edit,
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
          onTap: edit,
        );
      }

      return ListTile(
        key: const ValueKey('download-directory-setting'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: leading,
        title: Row(
          children: [
            Expanded(
              child: Text(
                l10n.tr("自定义下载目录", en: "Custom download directory"),
              ),
            ),
            const SizedBox(width: 8),
            status,
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tr("当前目录", en: "Current"),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    directoryLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              l10n.tr(
                "新下载任务会同时保存到此目录",
                en: "New downloads are also saved to this folder",
              ),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: edit,
      );
    },
  );
}

/// Backward-compatible name used by the settings page.
Widget downloadAndExportToSetting() => downloadDirectorySetting();
