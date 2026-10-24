import 'dart:io';

import 'package:clipboard/clipboard.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_styled_toast/flutter_styled_toast.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../configs/android_version.dart';

const coverShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(4.5)),
);

/// 显示一个toast
void defaultToast(BuildContext context, String title) {
  showToast(
    context.l10n.tr(title),
    context: context,
    position: StyledToastPosition.center,
    animation: StyledToastAnimation.scale,
    reverseAnimation: StyledToastAnimation.fade,
    duration: const Duration(seconds: 4),
    animDuration: const Duration(seconds: 1),
    curve: Curves.elasticOut,
    reverseCurve: Curves.linear,
  );
}

Future<T?> chooseListDialog<T>(BuildContext context,
    {required List<T> values, required String title, String? tips}) async {
  final l10n = context.l10n;
  final entries = values
      .map((value) => (label: l10n.tr('$value'), value: value))
      .toList(growable: false);
  return _showChoiceDialog<T>(
    context,
    title: l10n.tr(title),
    entries: entries,
    tips: tips == null ? null : l10n.tr(tips),
  );
}

Future<T?> chooseMapDialog<T>(
  BuildContext buildContext, {
  required String title,
  required Map<String, T> values,
  String? tips,
}) async {
  final l10n = buildContext.l10n;
  final entries = values.entries
      .map((entry) => (label: l10n.tr(entry.key), value: entry.value))
      .toList(growable: false);
  return _showChoiceDialog<T>(
    buildContext,
    title: l10n.tr(title),
    entries: entries,
    tips: tips == null ? null : l10n.tr(tips),
  );
}

Future<T?> _showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<({String label, T value})> entries,
  String? tips,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => Dialog(
      key: const ValueKey('app-choice-dialog'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 280,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * .64,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (tips != null && tips.trim().isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tips,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Material(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: .42,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(dialogContext).pop(entry.value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 19,
                              color: scheme.onSurfaceVariant,
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
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.l10n.tr('取消', en: 'Cancel')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> androidGalleryPermissionRequest() async {
  if (Platform.isAndroid && androidVersion < 33) {
    return await (Permission.storage.request()).isGranted;
  }
  return true;
}

Future<bool> androidMangeStorageRequest() async {
  if (Platform.isAndroid) {
    if (androidVersion < 30) {
      return await (Permission.storage.request()).isGranted;
    }
    return await (Permission.manageExternalStorage.request()).isGranted;
  }
  return true;
}

Future saveImageFileToGallery(BuildContext context, String path) async {
  if (!await androidGalleryPermissionRequest()) {
    throw Exception(context.l10n.tr("申请权限被拒绝", en: "Permission denied"));
  }
  if (Platform.isIOS || Platform.isAndroid) {
    await methods.saveImageFileToGallery(path);
    defaultToast(context, context.l10n.tr("保存成功", en: "Saved successfully"));
    return;
  }
  defaultToast(
      context, context.l10n.tr("暂不支持该平台", en: "Platform not supported"));
}

Future saveImageFileToFile(BuildContext context, String path) async {
  if (!await androidGalleryPermissionRequest()) {
    throw Exception(context.l10n.tr("申请权限被拒绝", en: "Permission denied"));
  }
  late String folder;
  if (Platform.isAndroid) {
    folder = await methods.picturesDir();
  } else if (Platform.isIOS) {
    folder = await methods.iosGetDocumentDir() + "/pictures";
  } else {
    var _f = await chooseFolder(context);
    if (_f != null) {
      folder = _f;
    }
  }
  try {
    await methods.copyPictureToFolder(folder, path);
    defaultToast(context, context.l10n.tr("保存成功", en: "Saved successfully"));
  } catch (e) {
    defaultToast(
      context,
      context.l10n.tr("保存失败", en: "Save failed") + " : $e",
    );
  }
}

Future<SortBy?> chooseSortBy(BuildContext context) async {
  final values = <String, SortBy>{
    sortByName(context, sortByDefault): sortByDefault,
    sortByName(context, sortByNew): sortByNew,
    sortByName(context, sortByLike): sortByLike,
    sortByName(context, sortByView): sortByView,
    sortByName(context, sortByViewDay): sortByViewDay,
    sortByName(context, sortByViewWeek): sortByViewWeek,
    sortByName(context, sortByViewMonth): sortByViewMonth,
  };
  return await chooseMapDialog(
    context,
    title: context.l10n.tr("请选择排序方式", en: "Choose sort mode"),
    values: values,
  );
}

String sortByName(BuildContext context, SortBy sortBy) {
  if (sortBy == sortByDefault) {
    return context.l10n.tr("默认", en: "Default");
  }
  if (sortBy == sortByNew) {
    return context.l10n.tr("最新", en: "Newest");
  }
  if (sortBy == sortByLike) {
    return context.l10n.tr("心", en: "Like");
  }
  if (sortBy == sortByView) {
    return context.l10n.tr("查看", en: "Views");
  }
  if (sortBy == sortByViewDay) {
    return context.l10n.tr("日榜", en: "Daily");
  }
  if (sortBy == sortByViewWeek) {
    return context.l10n.tr("周榜", en: "Weekly");
  }
  if (sortBy == sortByViewMonth) {
    return context.l10n.tr("月榜", en: "Monthly");
  }
  return context.l10n.tr(sortBy.toString());
}

/// 将字符串前面加0直至满足len位
String add0(int num, int len) {
  var rsp = "$num";
  while (rsp.length < len) {
    rsp = "0$rsp";
  }
  return rsp;
}

/// 打开网页或外部应用链接。
///
/// Android 11+ 上 `canLaunch` 可能因为包可见性返回 false。
/// 因此这里直接尝试启动，并在失败时返回 false，由调用方提供反馈。
Future<bool> openUrl(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return false;
  }
  if (Platform.isAndroid) {
    try {
      if (await methods.openExternalUrl(uri.toString())) {
        return true;
      }
    } catch (_) {
      // Fall through to url_launcher for compatibility.
    }
  }
  try {
    return await launch(
      uri.toString(),
      forceSafariVC: false,
    );
  } catch (_) {
    return false;
  }
}

Future<String?> displayTextInputDialog(BuildContext context,
    {String? title,
    String src = "",
    String? hint,
    String? desc,
    bool isPasswd = false}) async {
  final l10n = context.l10n;
  final controller = TextEditingController(text: src);
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  var obscureText = isPasswd;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        void submit() {
          Navigator.of(dialogContext).pop(controller.text);
        }

        return AlertDialog(
          key: const ValueKey('app-text-input-dialog'),
          title: Text(
            title == null ? l10n.tr('输入内容', en: 'Enter value') : l10n.tr(title),
            textAlign: TextAlign.center,
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('app-text-input-field'),
                    controller: controller,
                    autofocus: true,
                    obscureText: obscureText,
                    obscuringCharacter: '\u2022',
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      hintText: hint == null ? null : l10n.tr(hint),
                      prefixIcon: const Icon(Icons.keyboard_rounded, size: 19),
                      suffixIcon: isPasswd
                          ? IconButton(
                              tooltip: obscureText
                                  ? l10n.tr('显示内容', en: 'Show value')
                                  : l10n.tr('隐藏内容', en: 'Hide value'),
                              onPressed: () {
                                setState(() => obscureText = !obscureText);
                              },
                              icon: Icon(
                                obscureText
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 19,
                              ),
                            )
                          : null,
                    ),
                  ),
                  if (desc != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: .48,
                        ),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 17,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.tr(desc),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.tr('取消', en: 'Cancel')),
            ),
            FilledButton(
              key: const ValueKey('app-text-input-confirm'),
              onPressed: submit,
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

/// 复制内容到剪切板
void copyToClipBoard(BuildContext context, String string) {
  FlutterClipboard.copy(string);
  defaultToast(context, context.l10n.tr("已复制到剪切板", en: "Copied to clipboard"));
}

/// 显示一个确认框, 用户关闭弹窗以及选择否都会返回false, 仅当用户选择确定时返回true
Future<bool> confirmDialog(
    BuildContext context, String title, String content) async {
  final l10n = context.l10n;
  return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
                key: const ValueKey('app-confirm-dialog'),
                title: Text(l10n.tr(title)),
                content: SingleChildScrollView(
                  child: Text(
                    l10n.tr(content),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                  ),
                ),
                actions: [
                  TextButton(
                    child: Text(l10n.tr('取消', en: 'Cancel')),
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                  ),
                  FilledButton(
                    child: Text(l10n.confirm),
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                  ),
                ],
              )) ??
      false;
}

/// 复制对话框
void confirmCopy(BuildContext context, String content) async {
  if (await confirmDialog(
      context, context.l10n.tr("复制", en: "Copy"), content)) {
    copyToClipBoard(context, content);
  }
}

/// 选择一个文件夹用于保存文件
Future<String?> chooseFolder(BuildContext context) async {
  return FilePicker.platform.getDirectoryPath(
    dialogTitle: context.l10n.tr(
      "选择一个文件夹, 将文件保存到这里",
      en: "Choose a folder to save files",
    ),
  );
}
