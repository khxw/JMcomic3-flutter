part of '../comic_reader_screen.dart';

class _EpChooser extends StatefulWidget {
  final ChapterResponse chapter;
  final FutureOr Function(int, bool) onChangeEp;
  final List<Series>? series;

  const _EpChooser(this.chapter, this.onChangeEp, {this.series});

  @override
  State<StatefulWidget> createState() => _EpChooserState();
}

class _EpChooserState extends State<_EpChooser> {
  bool _selectionInFlight = false;

  Future<void> _selectChapter(int id) async {
    if (_selectionInFlight || !mounted) {
      return;
    }
    _selectionInFlight = true;
    try {
      if (mounted) {
        Navigator.of(context).pop();
      }
      await Future<void>.sync(() => widget.onChangeEp(id, false));
    } catch (error, stackTrace) {
      debugPrient(
          "chapter selection failed: ${error.runtimeType}/${stackTrace.runtimeType}");
    } finally {
      _selectionInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series ?? widget.chapter.series;
    final entries = series.isEmpty ? <Series>[] : _sortReaderSeries(series);
    final index = entries.indexWhere((entry) => entry.id == widget.chapter.id);
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('reader-chapter-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.tr('章节列表', en: 'Chapters'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entries.length} ${context.l10n.tr('章', en: 'chapters')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: .58),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.tr('关闭', en: 'Close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: .78),
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: Colors.white.withValues(alpha: .1),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    context.l10n.tr(
                      "无章节可选择",
                      en: "No chapters available",
                    ),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .68),
                    ),
                  ),
                )
              : zoomable.ZoomablePositionedList.builder(
                  enableZoom: false,
                  initialScrollIndex: index < 1 ? 0 : index - 1,
                  itemCount: entries.length,
                  itemBuilder: (BuildContext context, index) {
                    final entry = entries[index];
                    final selected = widget.chapter.id == entry.id;
                    return Padding(
                      key: ValueKey('reader-chapter-item-${entry.id}'),
                      padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
                      child: Material(
                        color: selected
                            ? theme.colorScheme.primary.withValues(alpha: .2)
                            : Colors.white.withValues(alpha: .055),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: selected
                                ? theme.colorScheme.primary
                                    .withValues(alpha: .58)
                                : Colors.white.withValues(alpha: .09),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _selectionInFlight
                              ? null
                              : () => unawaited(_selectChapter(entry.id)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.sort +
                                        (entry.name.isEmpty
                                            ? ''
                                            : ' · ${entry.name}'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 19,
                                    color: theme.colorScheme.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SettingPanel extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _SettingPanelState();
}

class _SettingPanelState extends State<_SettingPanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('reader-settings-sheet'),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.tr('阅读设置', en: 'Reading settings'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.tr(
              '调整阅读方向和操作方式',
              en: 'Adjust reading direction and controls',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: .58),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.25,
              children: [
                _settingCard(
                  icon: Icons.crop_rounded,
                  label: context.l10n.tr('阅读方向', en: 'Direction'),
                  value: readerDirectionName(currentReaderDirection, context),
                  onPressed: () async {
                    await chooseReaderDirection(context);
                    if (mounted) setState(() {});
                  },
                ),
                _settingCard(
                  icon: Icons.view_day_outlined,
                  label: context.l10n.tr('阅读模式', en: 'Layout'),
                  value: readerTypeName(currentReaderType, context),
                  onPressed: () async {
                    await chooseReaderType(context);
                    if (mounted) setState(() {});
                  },
                ),
                _settingCard(
                  icon: Icons.control_camera_outlined,
                  label: context.l10n.tr('操作方式', en: 'Controls'),
                  value: currentReaderControllerTypeName(context),
                  onPressed: () async {
                    await chooseReaderControllerType(context);
                    if (mounted) setState(() {});
                  },
                ),
                _settingCard(
                  icon: Icons.straighten_rounded,
                  label: context.l10n.tr('进度条位置', en: 'Progress bar'),
                  value: currentReaderSliderPositionName(context),
                  onPressed: () async {
                    await chooseReaderSliderPosition(context);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingCard({
    required IconData icon,
    required String label,
    required String value,
    required void Function() onPressed,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.white.withValues(alpha: .065),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: .1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: .55),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
