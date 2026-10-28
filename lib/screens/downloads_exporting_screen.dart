import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../configs/export_path.dart';
import '../configs/export_rename.dart';
import 'components/app_back_button.dart';
import 'components/right_click_pop.dart';
import 'downloads_export_ui.dart';

class DownloadsExportingScreen extends StatefulWidget {
  final List<int> idList;

  const DownloadsExportingScreen({Key? key, required this.idList})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsExportingScreenState();
}

class _DownloadsExportingScreenState extends State<DownloadsExportingScreen> {
  bool exporting = false;
  bool exported = false;
  bool exportFail = false;
  dynamic e;
  String exportMessage = '';
  var deleteExport = false;

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
          key: const ValueKey('batch-export-format-list'),
          padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 28),
          children: [
            ExportPageIntro(
              itemCount: widget.idList.length,
              includesIncomplete: false,
            ),
            const SizedBox(height: 14),
            ExportSectionCard(
              title: l10n.tr('漫画压缩包', en: 'Comic archives'),
              subtitle: l10n.tr(
                '每本漫画单独生成一个文件',
                en: 'One file per comic',
              ),
              icon: Icons.archive_outlined,
              children: [
                ExportFormatTile(
                  icon: Icons.folder_zip_outlined,
                  title: l10n.tr('JMI', en: 'JMI'),
                  subtitle: l10n.tr(
                    '保留原始图片和下载结构',
                    en: 'Original images and download structure',
                  ),
                  badge: l10n.tr('可重命名', en: 'Rename'),
                  onPressed: _exportJmis,
                ),
                const Divider(height: 1, indent: 64),
                ExportFormatTile(
                  icon: Icons.archive_outlined,
                  title: l10n.tr('JM.ZIP', en: 'JM.ZIP'),
                  subtitle: l10n.tr(
                    '标准 ZIP 压缩包',
                    en: 'Standard ZIP archive',
                  ),
                  badge: l10n.tr('ZIP', en: 'ZIP'),
                  onPressed: _exportZips,
                ),
                const Divider(height: 1, indent: 64),
                ExportFormatTile(
                  icon: Icons.photo_library_outlined,
                  title: l10n.tr('JPEGS.ZIP', en: 'JPEGS.ZIP'),
                  subtitle: l10n.tr(
                    '按图片格式打包为 ZIP',
                    en: 'Package image files as ZIP',
                  ),
                  badge: l10n.tr('图片', en: 'Images'),
                  onPressed: _exportJpegZips,
                ),
                const Divider(height: 1, indent: 64),
                ExportFormatTile(
                  icon: Icons.auto_stories_outlined,
                  title: l10n.tr('CBZ', en: 'CBZ'),
                  subtitle: l10n.tr(
                    '适用于漫画阅读器的压缩包',
                    en: 'Archive supported by comic readers',
                  ),
                  badge: 'CBZ',
                  onPressed: _exportCbzsZips,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExportSectionCard(
              title: l10n.tr('电子书', en: 'E-books'),
              subtitle: l10n.tr(
                '适合阅读器与跨设备查看',
                en: 'For readers and cross-device viewing',
              ),
              icon: Icons.book_outlined,
              children: [
                ExportFormatTile(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'PDF',
                  subtitle: l10n.tr(
                    '固定排版，可直接打开',
                    en: 'Fixed layout, ready to open',
                  ),
                  badge: 'PDF',
                  accent: Colors.deepOrange,
                  onPressed: _exportPdf,
                ),
                const Divider(height: 1, indent: 64),
                ExportFormatTile(
                  icon: Icons.menu_book_outlined,
                  title: 'EPUB',
                  subtitle: l10n.tr(
                    '适合电子书阅读器',
                    en: 'Optimized for e-book readers',
                  ),
                  badge: 'EPUB',
                  accent: Colors.teal,
                  onPressed: _exportEpubs,
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
                  key: const ValueKey('export-delete-after-export'),
                  title: Text(
                    l10n.tr(
                      '导出后删除下载的漫画',
                      en: 'Delete downloads after export',
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

  Future<void> _runSingleExport({
    required String confirmContent,
    required bool allowRename,
    required Future<void> Function(int id, String path, String? rename)
        exporter,
  }) async {
    final l10n = context.l10n;
    if (Platform.isMacOS) {
      await chooseEx(context);
    }
    if (!await confirmDialog(
      context,
      l10n.tr('导出确认', en: 'Export confirmation'),
      confirmContent + showExportPath(context),
    )) {
      return;
    }
    try {
      setState(() {
        exporting = true;
      });
      final path = await attachExportPath(context);
      for (var value in widget.idList) {
        final ab = await methods.downloadById(value);
        final albumName = ab?.album.name ?? '';
        if (!mounted) {
          return;
        }
        setState(() {
          exportMessage = l10n.tr('正在导出', en: 'Exporting') + ' : $albumName';
        });
        String? rename;
        if (allowRename && currentExportRename()) {
          rename = await displayTextInputDialog(
            context,
            title: l10n.tr('导出重命名', en: 'Export rename'),
            src: albumName,
          );
        }
        await exporter(value, path, rename);
      }
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

  Future<void> _exportJmis() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出JMI',
        en: 'Export selected comics as JMI',
      ),
      allowRename: true,
      exporter: (id, path, rename) => methods.export_jm_jmi_single(
        id,
        path,
        rename,
        deleteExport,
      ),
    );
  }

  Future<void> _exportPdf() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出PDF',
        en: 'Export selected comics as PDF',
      ),
      allowRename: false,
      exporter: (id, path, _) => methods.export_jm_pdf(
        id,
        path,
        deleteExport,
      ),
    );
  }

  Future<void> _exportCbzsZips() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出cbzs.zip',
        en: 'Export selected comics as cbzs.zip',
      ),
      allowRename: true,
      exporter: (id, path, rename) => methods.export_cbzs_zip_single(
        id,
        path,
        rename,
        deleteExport,
      ),
    );
  }

  Future<void> _exportZips() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出ZIP',
        en: 'Export selected comics as ZIP',
      ),
      allowRename: true,
      exporter: (id, path, rename) => methods.export_jm_zip_single(
        id,
        path,
        rename,
        deleteExport,
      ),
    );
  }

  Future<void> _exportJpegZips() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出JPEGS.ZIP',
        en: 'Export selected comics as JPEGS.ZIP',
      ),
      allowRename: true,
      exporter: (id, path, rename) => methods.export_jm_jpegs_zip_single(
        id,
        path,
        rename,
        deleteExport,
      ),
    );
  }

  Future<void> _exportEpubs() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出EPUB',
        en: 'Export selected comics as EPUB',
      ),
      allowRename: true,
      exporter: (id, path, rename) => methods.export_jm_epub_single(
        id,
        path,
        rename,
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
        key: const ValueKey('batch-export-format-page'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          leading: const AppBackButton(),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.tr('批量导出', en: 'Batch export')),
              Text(
                context.l10n.tr('选择导出格式', en: 'Choose a format'),
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
