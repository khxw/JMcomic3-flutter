/// 代理设置

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'download_and_export_to.dart';
import 'string_property.dart';

const String _propertyKey = "export_path";
late String _currentExportPath;

Future<String?> initExportPath() async {
  _currentExportPath = parseStringPropertyValue(
    await methods.loadProperty(_propertyKey),
    trim: true,
  );
  if (_currentExportPath.isEmpty) {
    if (Platform.isAndroid) {
      try {
        _currentExportPath = await methods.androidDefaultExportsDir();
      } catch (e) {
        _currentExportPath = "/sdcard/Download/jmtt2mic/exports";
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      _currentExportPath = await methods.getHomeDir();
      if (Platform.isMacOS) {
        _currentExportPath = _currentExportPath + "/Downloads";
      }
    } else if (Platform.isWindows) {
      _currentExportPath = "exports";
    }
  }
  return null;
}

String showExportPath(BuildContext context) {
  if (Platform.isIOS) {
    return context.l10n.tr(
      "\n\n随后可在文件管理中找到导出的内容",
      en: "\n\nThen you can find exported files in the Files app",
    );
  }
  return "\n\n${_effectiveExportPath()}";
}

String _effectiveExportPath() {
  return hasCustomDownloadDirectory
      ? currentDownloadAndExportTo
      : _currentExportPath;
}

Future _setExportPath(String folder) async {
  final value = parseStringPropertyValue(folder, trim: true);
  await methods.saveProperty(_propertyKey, value);
  _currentExportPath = value;
}

Widget displayExportPathInfo() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      final l10n = context.l10n;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      if (Platform.isIOS) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.tr(
                    "导出内容可在系统文件夹中找到",
                    en: "Exported files are available in the Files app",
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      }
      final path = _effectiveExportPath();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                await chooseEx(context);
                setState(() {});
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.folder_copy_outlined,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.tr(
                              "导出位置",
                              en: "Export location",
                            ),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            path.isEmpty
                                ? l10n.tr(
                                    "点击选择保存位置",
                                    en: "Tap to choose a location",
                                  )
                                : path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.edit_outlined,
                      size: 19,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (Platform.isAndroid)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.tr(
                        "如提示权限不足，可改选 Download 或 Documents 下的子文件夹",
                        en: "If permission is denied, choose a subfolder under Download or Documents",
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

Future<String> attachExportPath(BuildContext context) async {
  late String path;
  if (Platform.isIOS) {
    path = await methods.iosGetDocumentDir();
  } else {
    path = _effectiveExportPath();
    if (Platform.isAndroid && !await methods.androidDirectoryWritable(path)) {
      final selected = await methods.androidPickDownloadDirectory();
      if (selected == null || selected.trim().isEmpty) {
        throw Exception(context.l10n.tr("申请权限被拒绝", en: "Permission denied"));
      }
      path = selected;
      await _setExportPath(path);
    }
  }
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await methods.mkdirs(path);
  } else if (Platform.isAndroid) {
    await methods.androidMkdirs(path);
  }
  return path;
}

Future chooseEx(BuildContext context) async {
  String? choose = Platform.isAndroid
      ? await methods.androidPickDownloadDirectory()
      : await chooseFolder(context);
  if (choose != null) {
    await _setExportPath(choose);
  }
}
