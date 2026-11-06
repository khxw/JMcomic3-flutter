import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import '../configs/is_pro.dart';
import 'components/app_back_button.dart';
import 'components/right_click_pop.dart';
import 'download_import_shared.dart';

// 导入
class DownloadImportScreen extends StatefulWidget {
  const DownloadImportScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadImportScreenState();
}

class _DownloadImportScreenState extends State<DownloadImportScreen> {
  bool _importing = false;
  String _importMessage = "";
  bool _importFailed = false;

  @override
  void initState() {
    // registerEvent(_onMessageChange, "EXPORT");
    super.initState();
  }

  @override
  void dispose() {
    // unregisterEvent(_onMessageChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(
      child: buildScreen(context),
      context: context,
      canPop: !_importing,
    );
  }

  Widget buildScreen(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_importing) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          leading: const AppBackButton(),
          title: Text(context.l10n.tr('导入下载', en: 'Import downloads')),
        ),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 28),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .55),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  _importMessage.isEmpty
                      ? context.l10n.tr('正在导入...', en: 'Importing...')
                      : _importMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.tr(
                    '请保持应用在前台，不要关闭页面。',
                    en: 'Keep the app open while the import completes.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.l10n.tr('导入下载', en: 'Import downloads')),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _buildIntroCard(context),
                if (_importMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildFeedbackCard(context),
                ],
                const SizedBox(height: 14),
                _fileImportButton(),
                const SizedBox(height: 12),
                _importDirFilesZipButton(),
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 14),
                  _buildAndroidTip(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntroCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.move_to_inbox_rounded,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr(
                    '导入已下载漫画',
                    en: 'Import downloaded comics',
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  context.l10n.tr(
                    '从压缩包或 jmi 文件恢复到下载列表。',
                    en: 'Restore comics to Downloads from an archive or jmi file.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _importFailed ? scheme.error : scheme.primary;
    return Container(
      key: const ValueKey('download-import-feedback'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _importFailed
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _importMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAndroidTip(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .48),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 19,
            color: scheme.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              context.l10n.tr(
                '如果 Android 提示权限不足，请先将文件放到 Download 或 Documents 下的子文件夹，再重新选择。',
                en: 'If Android reports a permission error, move the file into a subfolder under Download or Documents and select it again.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureImportAllowed() async {
    if (!hasProAccess) {
      defaultToast(
        context,
        context.l10n.tr(
          "发电才能使用哦~",
          en: "Pro is required for this feature",
        ),
      );
      return false;
    }
    final permissionDeniedMessage =
        context.l10n.tr("申请权限被拒绝", en: "Permission denied");
    if (!await androidMangeStorageRequest()) {
      if (!mounted) {
        return false;
      }
      defaultToast(context, permissionDeniedMessage);
      return false;
    }
    return true;
  }

  void _setImportState({bool? importing, String? message, bool? failed}) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (importing != null) {
        _importing = importing;
      }
      if (message != null) {
        _importMessage = message;
      }
      if (failed != null) {
        _importFailed = failed;
      }
    });
  }

  /// 导入会跨文件选择器和 Rust 后端执行；用户在等待时可能返回上一页。
  /// 所有状态更新集中到这里并检查 mounted，避免异步回调更新已销毁的页面。
  Future<void> _runImport(Future<void> Function() importTask) async {
    final successMessage = context.l10n.tr("导入成功", en: "Import succeeded");
    final failedPrefix = context.l10n.tr("导入失败", en: "Import failed");

    _setImportState(importing: true, message: "", failed: false);
    try {
      await importTask();
      _setImportState(message: successMessage, failed: false);
    } catch (e) {
      _setImportState(message: "$failedPrefix $e", failed: true);
    } finally {
      _setImportState(importing: false);
    }
  }

  Future<String?> _chooseImportFilePath() async {
    if (Platform.isAndroid) {
      return FilesystemPicker.open(
        title: context.l10n.tr('选择文件', en: 'Select file'),
        context: context,
        rootDirectory: Directory("/storage/emulated/0"),
        fsType: FilesystemType.file,
        folderIconColor: Colors.teal,
        allowedExtensions: ['.zip', '.jmi'],
        fileTileSelectMode: FileTileSelectMode.wholeTile,
      );
    }

    final files = await FilePicker.platform.pickFiles(
      dialogTitle: context.l10n.tr('选择要导入的文件', en: 'Choose file to import'),
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['zip', 'jmi'],
    );
    return files != null && files.count > 0 ? files.paths[0] : null;
  }

  Widget _fileImportButton() {
    return _ImportActionCard(
      key: const ValueKey('download-import-file'),
      icon: Icons.insert_drive_file_outlined,
      title: context.l10n.tr(
        '导入单个文件',
        en: 'Import a single file',
      ),
      description: context.l10n.tr(
        '选择已下载的漫画压缩包或 jmi 文件。',
        en: 'Choose a downloaded comic archive or jmi file.',
      ),
      formats: const ['JM.ZIP', 'JMI'],
      proRequired: !hasProAccess,
      onTap: () async {
        if (!await _ensureImportAllowed()) {
          return;
        }
        if (!mounted) {
          return;
        }
        final path = await _chooseImportFilePath();
        if (!mounted) {
          return;
        }
        if (path == null) {
          return;
        }
        final kind = detectDownloadImportArchiveKind(path);
        if (kind == null) {
          defaultToast(
            context,
            context.l10n.tr(
              "Only .jm.zip and .jmi files are supported",
              en: "Only .jm.zip and .jmi files are supported",
            ),
          );
          return;
        }
        await _runImport(() async {
          if (kind == DownloadImportArchiveKind.jmZip) {
            await methods.import_jm_zip(path);
          } else {
            await methods.import_jm_jmi(path);
          }
        });
      },
    );
  }

  Widget _importDirFilesZipButton() {
    return _ImportActionCard(
      key: const ValueKey('download-import-folder'),
      icon: Icons.folder_open_rounded,
      title: context.l10n.tr(
        '从文件夹批量导入',
        en: 'Import from a folder',
      ),
      description: context.l10n.tr(
        '自动导入所选文件夹内的全部 zip 与 jmi 文件。',
        en: 'Import every zip and jmi file inside the selected folder.',
      ),
      formats: [
        context.l10n.tr('批量', en: 'Batch'),
        'ZIP',
        'JMI',
      ],
      proRequired: !hasProAccess,
      onTap: () async {
        if (!await _ensureImportAllowed()) {
          return;
        }
        if (!mounted) {
          return;
        }
        late String? path;
        try {
          path = await chooseFolder(context);
        } catch (e) {
          if (!mounted) {
            return;
          }
          defaultToast(context, "$e");
          return;
        }
        if (!mounted) {
          return;
        }
        if (path != null) {
          final importPath = path;
          await _runImport(() async {
            await methods.import_jm_dir(importPath);
          });
        }
      },
    );
  }
}

class _ImportActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<String> formats;
  final bool proRequired;
  final VoidCallback onTap;

  const _ImportActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.formats,
    required this.proRequired,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = proRequired ? scheme.onSurfaceVariant : scheme.onSurface;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: scheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (proRequired)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              context.l10n.tr(
                                '需要发电',
                                en: 'Pro required',
                              ),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: formats
                          .map(
                            (format) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: scheme.outlineVariant
                                      .withValues(alpha: .65),
                                ),
                              ),
                              child: Text(
                                format,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
