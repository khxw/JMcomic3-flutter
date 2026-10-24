import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_info_card.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';
import 'package:jmcomic3/screens/components/right_click_pop.dart';

import 'comic_download_shared.dart';
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
        titleSpacing: 0,
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
        final usableWidth = contentWidth - 32;
        final columns = (usableWidth / 176).floor().clamp(1, 4);
        return CustomScrollView(
          key: const ValueKey('comic-download-chapters-scroll'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 8, side, 0),
              sliver: SliverToBoxAdapter(
                child: ComicInfoCard(
                  albumToSimple(widget.album),
                  link: true,
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 12, side, 0),
              sliver: SliverToBoxAdapter(
                child: _DownloadOverview(
                  selected: _selectedEps.length,
                  tasked: _taskedEps.length,
                  total: series.length,
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 18, side, 10),
              sliver: SliverToBoxAdapter(
                child: _ChapterSectionHeader(total: series.length),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 108),
              sliver: SliverGrid.builder(
                itemCount: series.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 92,
                ),
                itemBuilder: (context, index) {
                  final chapter = series[index];
                  final state = downloadChapterVisualState(
                    _taskedEps,
                    _selectedEps,
                    chapter.id,
                  );
                  return _ChapterCard(
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
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DownloadOverview extends StatelessWidget {
  final int selected;
  final int tasked;
  final int total;

  const _DownloadOverview({
    required this.selected,
    required this.tasked,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectable = (total - tasked).clamp(0, total);
    final progress = selectable <= 0 ? 0.0 : selected / selectable;
    return Container(
      key: const ValueKey('comic-download-overview'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: .13),
            scheme.secondary.withValues(alpha: .07),
          ],
        ),
        border: Border.all(
          color: scheme.primary.withValues(alpha: .16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.vertical_align_bottom_rounded,
                  color: scheme.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.tr(
                        '已选择 $selected 话',
                        en: '$selected selected',
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      context.l10n.tr(
                        '共 $total 话 · 已下载 $tasked 话',
                        en: '$total chapters · $tasked downloaded',
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                "${(progress * 100).round()}%",
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
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
        ],
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
    final foreground = tasked
        ? scheme.onSurfaceVariant
        : selected
            ? scheme.onPrimaryContainer
            : scheme.onSurface;
    final background = tasked
        ? scheme.surfaceContainerHighest.withValues(alpha: .55)
        : selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow;
    final border = selected
        ? scheme.primary.withValues(alpha: .55)
        : scheme.outline.withValues(alpha: tasked ? .08 : .16);
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    tasked
                        ? Icons.download_done_rounded
                        : selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                    key: ValueKey(state),
                    size: 21,
                    color: tasked
                        ? scheme.onSurfaceVariant
                        : selected
                            ? scheme.primary
                            : scheme.outline,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
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
                        tasked
                            ? context.l10n.tr('已下载', en: 'Downloaded')
                            : selected
                                ? context.l10n.tr('已选择', en: 'Selected')
                                : context.l10n.tr(
                                    '§ ${chapter.sort}',
                                    en: '§ ${chapter.sort}',
                                  ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: foreground.withValues(alpha: .72),
                        ),
                      ),
                    ],
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
    return DecoratedBox(
      key: const ValueKey('comic-download-action-bar'),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outline.withValues(alpha: .12),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.tr(
                        '已选择 $selected / $selectable',
                        en: '$selected of $selectable selected',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('comic-download-clear'),
                    onPressed: selected == 0 ? null : onClear,
                    child: Text(context.l10n.tr('清除', en: 'Clear')),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(14) / 14;
                  final stackActions =
                      constraints.maxWidth < 360 || textScale > 1.25;
                  final selectAll = OutlinedButton(
                    key: const ValueKey('comic-download-select-all'),
                    onPressed: !ready || selectable == 0 ? null : onSelectAll,
                    child: Text(
                      context.l10n.tr('全选', en: 'Select all'),
                    ),
                  );
                  final download = FilledButton(
                    key: const ValueKey('comic-download-confirm'),
                    onPressed: !ready
                        ? null
                        : selectable == 0
                            ? onViewDownloads
                            : selected == 0 || submitting
                                ? null
                                : onSubmit,
                    child: selectable == 0
                        ? Text(
                            context.l10n.tr('查看下载', en: 'View downloads'),
                          )
                        : submitting
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                context.l10n.tr(
                                  '下载 $selected',
                                  en: 'Download $selected',
                                ),
                              ),
                  );
                  if (stackActions) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        selectAll,
                        const SizedBox(height: 7),
                        download,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: selectAll),
                      const SizedBox(width: 10),
                      Expanded(child: download),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
