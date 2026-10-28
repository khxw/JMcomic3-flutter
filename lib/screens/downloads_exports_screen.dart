import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';
import 'components/app_back_button.dart';
import 'components/right_click_pop.dart';
import 'downloads_exporting_screen.dart';
import 'downloads_export_shared.dart';
import 'downloads_export_ui.dart';

class DownloadsExportScreen extends StatefulWidget {
  const DownloadsExportScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsExportScreenState();
}

class _DownloadsExportScreenState extends State<DownloadsExportScreen> {
  late Future<List<DownloadAlbum>> _downloadsFuture;

  @override
  void initState() {
    _downloadsFuture = _loadDownloads();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      key: const ValueKey('batch-export-select-page'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.tr("批量导出", en: "Batch export")),
            Text(
              context.l10n.tr("仅导出已下载的内容", en: "Completed downloads"),
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
      body: ContentBuilder(
        future: _downloadsFuture,
        onRefresh: _refreshDownloads,
        successBuilder: (
          BuildContext context,
          AsyncSnapshot<List<DownloadAlbum>> snapshot,
        ) {
          final albums = snapshot.requireData;
          return DownloadExportSelectionView(
            albums: albums,
            selected: selected,
            modeLabel: context.l10n.tr('仅已下载', en: 'Completed only'),
            onToggle: (album) {
              setState(() {
                toggleSelectedDownloadId(selected, album.id);
              });
            },
            onSelectAll: () => _selectAll(albums),
            onClear: () {
              setState(selected.clear);
            },
            onContinue: _goToExport,
          );
        },
      ),
    );
  }

  Set<int> selected = <int>{};

  Future<List<DownloadAlbum>> _loadDownloads() {
    return loadDownloadAlbums((album) => album.isDownloaded);
  }

  Future<void> _refreshDownloads() async {
    final future = _loadDownloads();
    setState(() {
      _downloadsFuture = future;
    });
    await future;
  }

  void _selectAll(List<DownloadAlbum> albums) {
    final ids = albums.map((album) => album.id).toSet();
    setState(() {
      if (ids.isNotEmpty && ids.every(selected.contains)) {
        selected.clear();
      } else {
        selected
          ..clear()
          ..addAll(ids);
      }
    });
  }

  Future<void> _goToExport() async {
    if (selected.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DownloadsExportingScreen(
          idList: selected.toList(growable: false),
        ),
      ),
    );
    if (!mounted) return;
    final previous = Set<int>.from(selected);
    final future = _loadDownloads();
    setState(() {
      _downloadsFuture = future;
      selected = <int>{};
    });
    try {
      final latest = await future;
      if (!mounted) return;
      setState(() {
        selected = restoreSelectedIdSet(previous, latest);
      });
    } catch (_) {
      // ContentBuilder owns the retry state when the refreshed list fails.
    }
  }
}
