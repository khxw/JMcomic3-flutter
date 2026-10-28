import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../configs/export_path.dart';
import 'components/app_back_button.dart';
import 'components/right_click_pop.dart';
import 'downloads_export_ui.dart';

class DownloadsExportingScreen2 extends StatefulWidget {
  final List<int> idList;

  const DownloadsExportingScreen2({Key? key, required this.idList})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsExportingScreen2State();
}

class _DownloadsExportingScreen2State extends State<DownloadsExportingScreen2> {
  bool exporting = false;
  bool exported = false;
  bool exportFail = false;
  dynamic e;
  String exportMessage = '';
  bool deleteExport = false;

  Widget _body() {
    final l10n = context.l10n;
    if (exporting) {
      return ExportProgressPanel(
        label: exportMessage.isEmpty
            ? l10n.tr('正在导出', en: 'Exporting')
            : l10n.tr(exportMessage),
        itemCount: widget.idList.length,
      );
    }
    if (exportFail) {
      return ExportResultPanel(
        success: false,
        title: l10n.tr('导出失败', en: 'Export failed'),
        message: '$e',
        onReset: () {
          setState(() {
            exportFail = false;
            e = null;
            exportMessage = '';
          });
        },
      );
    }
    if (exported) {
      return ExportResultPanel(
        success: true,
        title: l10n.tr('导出成功', en: 'Export succeeded'),
        message: l10n.tr(
          '文件已保存到导出目录，可返回文件管理器查看。',
          en: 'Files were saved to the export folder.',
        ),
        onReset: () => Navigator.of(context).maybePop(),
      );
    }
    final horizontal = MediaQuery.sizeOf(context).width >= 760 ? 24.0 : 14.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          key: const ValueKey('batch-export-incomplete-format-list'),
          padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 28),
          children: [
            ExportPageIntro(
              itemCount: widget.idList.length,
              includesIncomplete: true,
            ),
            const SizedBox(height: 14),
            ExportSectionCard(
              title: l10n.tr('选择导出方式', en: 'Export format'),
              subtitle: l10n.tr(
                '未完成的漫画也会一并处理',
                en: 'Unfinished comics are included',
              ),
              icon: Icons.drive_file_move_outline,
              children: [
                ExportFormatTile(
                  icon: Icons.folder_copy_outlined,
                  title: l10n.tr('图片文件夹', en: 'Image folders'),
                  subtitle: l10n.tr(
                    '按漫画分别生成图片文件夹',
                    en: 'Create an image folder for each comic',
                  ),
                  badge: l10n.tr('文件夹', en: 'Folder'),
                  onPressed: _exportJpegs,
                ),
                const Divider(height: 1, indent: 64),
                ExportFormatTile(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'PDF',
                  subtitle: l10n.tr(
                    '逐本生成 PDF 文档',
                    en: 'Create one PDF per comic',
                  ),
                  badge: 'PDF',
                  accent: Colors.deepOrange,
                  onPressed: _exportPdf2,
                ),
                const Divider(height: 1, indent: 64),
                ExportFormatTile(
                  icon: Icons.menu_book_outlined,
                  title: 'EPUB',
                  subtitle: l10n.tr(
                    '生成适合阅读器的电子书',
                    en: 'Create reader-friendly e-books',
                  ),
                  badge: 'EPUB',
                  accent: Colors.teal,
                  onPressed: _exportEpub,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExportSectionCard(
              title: l10n.tr('保存位置与选项', en: 'Location and options'),
              icon: Icons.tune_rounded,
              children: [
                displayExportPathInfo(),
                const Divider(height: 1),
                SwitchListTile(
                  key: const ValueKey('export-delete-source-after-export'),
                  title: Text(
                    l10n.tr(
                      '导出后删除原文件',
                      en: 'Delete source files after export',
                    ),
                  ),
                  subtitle: Text(
                    l10n.tr(
                      '导出成功后释放本地下载文件',
                      en: 'Free local download files after a successful export',
                    ),
                  ),
                  value: deleteExport,
                  onChanged: (value) {
                    setState(() {
                      deleteExport = value;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickPath() async {
    try {
      return await attachExportPath(context);
    } catch (e) {
      defaultToast(context, '$e');
      return null;
    }
  }

  Future<void> _runBatchExport({
    required Future<void> Function(String path) exporter,
  }) async {
    final path = await _pickPath();
    debugPrient('path $path');
    if (path == null) {
      return;
    }
    try {
      setState(() {
        exporting = true;
      });
      await exporter(path);
      exported = true;
    } catch (err) {
      e = err;
      exportFail = true;
    } finally {
      if (mounted) {
        setState(() {
          exporting = false;
        });
      }
    }
  }

  Future<void> _exportJpegs() {
    return _runBatchExport(
      exporter: (path) => methods.export_jm_jpegs(
        widget.idList,
        path,
        deleteExport,
      ),
    );
  }

  Future<void> _exportPdf2() {
    return _runBatchExport(
      exporter: (path) async {
        for (var id in widget.idList) {
          await methods.export_jm_pdf2(
            id,
            path,
            deleteExport,
          );
        }
      },
    );
  }

  Future<void> _exportEpub() {
    return _runBatchExport(
      exporter: (path) => methods.export_jm_epub(
        widget.idList,
        path,
        deleteExport,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(
      child: buildScreen(context),
      context: context,
      canPop: !exporting,
    );
  }

  Widget buildScreen(BuildContext context) {
    return WillPopScope(
      child: Scaffold(
        key: const ValueKey('batch-export-incomplete-format-page'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          leading: const AppBackButton(),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.tr('批量导出', en: 'Batch export')),
              Text(
                context.l10n.tr(
                  '包含未完成的下载',
                  en: 'Includes unfinished downloads',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          surfaceTintColor: Colors.transparent,
        ),
        body: _body(),
      ),
      onWillPop: () async {
        if (exporting) {
          defaultToast(
            context,
            context.l10n.tr('导出中, 请稍后', en: 'Exporting, please wait'),
          );
          return false;
        }
        return true;
      },
    );
  }
}
