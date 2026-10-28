import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';
import 'package:jmcomic3/screens/components/images.dart';
import 'package:jmcomic3/screens/components/right_click_pop.dart';

import 'comic_download_shared.dart';
import 'components/app_back_button.dart';
import 'downloads_screen.dart';

class ComicDownloadScreen extends StatefulWidget {
  final AlbumResponse album;

  const ComicDownloadScreen(this.album, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicDownloadScreenState();
}

class _ComicDownloadScreenState extends State<ComicDownloadScreen> {
  late Future<void> _innerDownloadFuture;
  final Set<int> _taskedEps = {};
  final Set<int> _selectedEps = {};
  bool _ready = false;
  bool _submitting = false;

  List<Series> get _series => downloadSeriesForAlbum(widget.album);

  @override
  void initState() {
    super.initState();
    _innerDownloadFuture = _init();
  }

  Future<void> _init() async {
    _taskedEps.clear();
    final task = await methods.downloadById(widget.album.id);
    if (task != null) {
      _taskedEps.addAll(task.chapters.map((chapter) => chapter.id));
    }
    _selectedEps.removeWhere(_taskedEps.contains);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _ready = false;
        _innerDownloadFuture = _init();
      });
    }
    await _innerDownloadFuture;
  }

  void _selectAll() {
    setState(() {
      _selectedEps
        ..clear()
        ..addAll(selectableDownloadChapterIds(_series, _taskedEps));
    });
  }

  void _clearSelection() {
    if (_selectedEps.isEmpty) return;
    setState(_selectedEps.clear);
  }

  void _selectRecent() {
    final recent = <int>[];
    for (final chapter in _series.reversed) {
      if (_taskedEps.contains(chapter.id)) continue;
      recent.add(chapter.id);
      if (recent.length == 10) break;
    }
    setState(() {
      _selectedEps
        ..clear()
        ..addAll(recent);
    });
  }

  Future<void> _submitDownload() async {
    if (_submitting) return;
    final chapters = selectedDownloadChapters(_series, _selectedEps);
    if (chapters.isEmpty) {
      defaultToast(
        context,
        context.l10n.tr('请先选择章节', en: 'Select chapters first'),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await methods.createDownload(
        DownloadCreate(
          album: DownloadCreateAlbum(
            id: widget.album.id,
            name: widget.album.name,
            author: widget.album.author,
            tags: widget.album.tags,
            works: widget.album.works,
            description: widget.album.description,
          ),
          chapters: chapters,
        ),
      );
      if (!mounted) return;
      _openDownloads();
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      defaultToast(context, '$error');
    }
  }

  void _openDownloads() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DownloadsScreen(
          initialDownloadId: widget.album.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(
      child: buildScreen(context),
      context: context,
    );
  }

  Widget buildScreen(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('comic-download-page'),
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: const AppBackButton(),
        titleSpacing: 8,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.tr('下载', en: 'Download')),
            Text(
              widget.album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.tr('下载列表', en: 'Downloads'),
            onPressed: _openDownloads,
            icon: const Icon(Icons.download_done_rounded),
          ),
        ],
      ),
      body: ContentBuilder<void>(
        future: _innerDownloadFuture,
        onRefresh: _refresh,
        successBuilder: (context, _) => _buildContent(context),
      ),
      bottomNavigationBar: _DownloadActionBar(
        selected: _selectedEps.length,
        selectable: selectableDownloadChapterIds(_series, _taskedEps).length,
        ready: _ready,
        submitting: _submitting,
        onSelectAll: _selectAll,
        onClear: _clearSelection,
        onSubmit: _submitDownload,
        onViewDownloads: _openDownloads,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final series = _series;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth =
            constraints.maxWidth > 920 ? 920.0 : constraints.maxWidth;
        final side = (constraints.maxWidth - contentWidth) / 2 + 16;
        return CustomScrollView(
          key: const ValueKey('comic-download-chapters-scroll'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 6, side, 0),
              sliver: SliverToBoxAdapter(
                child: _DownloadComicHeader(
                  album: widget.album,
                  total: series.length,
                  tasked: _taskedEps.length,
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 10, side, 0),
              sliver: SliverToBoxAdapter(
                child: _DownloadOverview(
                  selected: _selectedEps.length,
                  tasked: _taskedEps.length,
                  total: series.length,
                  ready: _ready,
                  onSelectAll: _selectAll,
                  onClear: _clearSelection,
                  onSelectRecent: _selectRecent,
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 16, side, 8),
              sliver: SliverToBoxAdapter(
                child: _ChapterSectionHeader(total: series.length),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 122),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final chapter = series[index];
                    final state = downloadChapterVisualState(
                      _taskedEps,
                      _selectedEps,
                      chapter.id,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _ChapterCard(
                        chapter: chapter,
                        state: state,
                        onTap: state == DownloadChapterVisualState.tasked
                            ? null
                            : () {
                                setState(() {
                                  toggleSelectedDownloadChapterId(
                                    _selectedEps,
                                    _taskedEps,
                                    chapter.id,
                                  );
                                });
                              },
                      ),
                    );
                  },
                  childCount: series.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DownloadComicHeader extends StatelessWidget {
  final AlbumResponse album;
  final int total;
  final int tasked;

  const _DownloadComicHeader({
    required this.album,
    required this.total,
    required this.tasked,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final author = album.author.join(' / ');
    return Container(
      key: const ValueKey('comic-download-comic-header'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: .16),
            scheme.surfaceContainerLow.withValues(alpha: .9),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: .15)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            height: 98,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: JM3x4Cover(comicId: album.id),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  author.isEmpty
                      ? context.l10n.tr('未知作者', en: 'Unknown author')
                      : author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _metaPill(
                      context,
                      context.l10n.tr('共 $total 话', en: '$total chapters'),
                    ),
                    _metaPill(
                      context,
                      context.l10n
                          .tr('已下载 $tasked 话', en: '$tasked downloaded'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaPill(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .56),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .4)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 9,
            ),
      ),
    );
  }
}

class _DownloadOverview extends StatelessWidget {
  final int selected;
  final int tasked;
  final int total;
  final bool ready;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onSelectRecent;

  const _DownloadOverview({
    required this.selected,
    required this.tasked,
    required this.total,
    required this.ready,
    required this.onSelectAll,
    required this.onClear,
    required this.onSelectRecent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectable = (total - tasked).clamp(0, total);
    final progress = selectable <= 0 ? 0.0 : selected / selectable;
    return Container(
      key: const ValueKey('comic-download-overview'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$selected',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        context.l10n.tr('话已选择', en: 'selected'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    context.l10n.tr(
                      '共 $total 话\n已下载 $tasked 话',
                      en: '$total chapters\n$tasked downloaded',
                    ),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: scheme.primary.withValues(alpha: .1),
            ),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _quickAction(
                context: context,
                key: const ValueKey('comic-download-overview-select-all'),
                label: context.l10n.tr('全选未下载', en: 'Select available'),
                primary: true,
                onPressed: ready && selectable > 0 ? onSelectAll : null,
              ),
              _quickAction(
                context: context,
                key: const ValueKey('comic-download-overview-clear'),
                label: context.l10n.tr('清除', en: 'Clear'),
                onPressed: selected > 0 ? onClear : null,
              ),
              _quickAction(
                context: context,
                key: const ValueKey('comic-download-overview-recent'),
                label: context.l10n.tr('最近 10 话', en: 'Latest 10'),
                onPressed: ready && selectable > 0 ? onSelectRecent : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickAction({
    required BuildContext context,
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 30,
      child: TextButton(
        key: key,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: primary ? scheme.primary : scheme.onSurfaceVariant,
          backgroundColor: primary
              ? scheme.primary.withValues(alpha: .1)
              : scheme.surfaceContainerHighest.withValues(alpha: .7),
          side: BorderSide(
            color: primary
                ? scheme.primary.withValues(alpha: .18)
                : scheme.outlineVariant.withValues(alpha: .35),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
          ),
          textStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

class _ChapterSectionHeader extends StatelessWidget {
  final int total;

  const _ChapterSectionHeader({required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.tr('选择章节', en: 'Select chapters'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            context.l10n.tr('共 $total 话', en: '$total chapters'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChapterCard extends StatelessWidget {
  final Series chapter;
  final DownloadChapterVisualState state;
  final VoidCallback? onTap;

  const _ChapterCard({
    required this.chapter,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = state == DownloadChapterVisualState.selected;
    final tasked = state == DownloadChapterVisualState.tasked;
    final foreground = tasked ? scheme.onSurfaceVariant : scheme.onSurface;
    final background = tasked
        ? scheme.surfaceContainerLow.withValues(alpha: .62)
        : selected
            ? scheme.primary.withValues(alpha: .09)
            : scheme.surfaceContainerLow;
    final border = selected
        ? scheme.primary.withValues(alpha: .38)
        : scheme.outlineVariant.withValues(alpha: tasked ? .18 : .42);
    final title = chapter.name.trim().isEmpty
        ? context.l10n.tr(
            '第 ${chapter.sort} 话',
            en: 'Chapter ${chapter.sort}',
          )
        : chapter.name;
    return AnimatedContainer(
      key: ValueKey('comic-download-chapter-${chapter.id}'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 21,
                  height: 21,
                  decoration: BoxDecoration(
                    color: tasked
                        ? scheme.tertiary.withValues(alpha: .13)
                        : selected
                            ? scheme.primary
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: tasked
                          ? Colors.transparent
                          : selected
                              ? scheme.primary
                              : scheme.outline,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    selected || tasked ? Icons.check_rounded : null,
                    size: 14,
                    color: selected
                        ? scheme.onPrimary
                        : tasked
                            ? scheme.tertiary
                            : null,
                  ),
                ),
                const SizedBox(width: 9),
                Container(
                  width: 36,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary.withValues(alpha: .13)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(
                      chapter.sort,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color:
                            selected ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.l10n.tr(
                          '第 ${chapter.sort} 话',
                          en: 'Chapter ${chapter.sort}',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 68),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      tasked
                          ? context.l10n.tr('已下载', en: 'Downloaded')
                          : selected
                              ? context.l10n.tr('已选择', en: 'Selected')
                              : '',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tasked ? scheme.tertiary : scheme.primary,
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadActionBar extends StatelessWidget {
  final int selected;
  final int selectable;
  final bool ready;
  final bool submitting;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onSubmit;
  final VoidCallback onViewDownloads;

  const _DownloadActionBar({
    required this.selected,
    required this.selectable,
    required this.ready,
    required this.submitting,
    required this.onSelectAll,
    required this.onClear,
    required this.onSubmit,
    required this.onViewDownloads,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final download = FilledButton(
      key: const ValueKey('comic-download-confirm'),
      onPressed: !ready
          ? null
          : selectable == 0
              ? onViewDownloads
              : selected == 0 || submitting
                  ? null
                  : onSubmit,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: selectable == 0
            ? Text(context.l10n.tr('查看下载', en: 'View downloads'))
            : submitting
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    context.l10n.tr(
                      '下载 $selected 话',
                      en: 'Download $selected',
                    ),
                  ),
      ),
    );
    return SafeArea(
      key: const ValueKey('comic-download-action-bar'),
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(21),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: .28),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _barAction(
              context,
              key: const ValueKey('comic-download-clear'),
              icon: Icons.delete_outline_rounded,
              label: context.l10n.tr('清除', en: 'Clear'),
              onPressed: selected == 0 ? null : onClear,
            ),
            _barAction(
              context,
              key: const ValueKey('comic-download-select-all'),
              icon: Icons.select_all_rounded,
              label: context.l10n.tr('全选', en: 'Select all'),
              onPressed: !ready || selectable == 0 ? null : onSelectAll,
            ),
            const SizedBox(width: 4),
            Expanded(child: download),
          ],
        ),
      ),
    );
  }

  Widget _barAction(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 52,
      height: 48,
      child: TextButton(
        key: key,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          padding: EdgeInsets.zero,
          minimumSize: const Size(52, 48),
          maximumSize: const Size(52, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
