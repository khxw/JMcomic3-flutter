import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:another_xlider/another_xlider.dart';
import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:photo_view/photo_view.dart';
import 'package:zoomable_positioned_list/zoomable_positioned_list.dart'
    as zoomable;
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/reader_controller_type.dart';
import 'package:jmcomic3/configs/reader_direction.dart';
import 'package:jmcomic3/configs/reader_preload.dart';
import 'package:jmcomic3/configs/reader_slider_position.dart';
import 'package:jmcomic3/configs/reader_type.dart';
import 'package:jmcomic3/configs/super_resolution.dart';
import 'package:jmcomic3/configs/two_page_direction.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_error.dart';
import 'package:jmcomic3/screens/components/content_loading.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../configs/ignore_view_log.dart';
import '../configs/no_animation.dart';
import '../configs/volume_key_control.dart';
import '../basic/reader_system_ui.dart';
import 'components/app_back_button.dart';
import 'components/images.dart';
import 'components/right_click_pop.dart';
import '../basic/reader_pages.dart';
import '../basic/page_pairing.dart';
import 'reader/reader_position.dart';

part 'reader/reader_viewers.dart';
part 'reader/reader_panels.dart';

class ComicReaderScreen extends StatefulWidget {
  final ComicBasic comic;
  final List<Series> series;
  final int chapterId;
  final int initRank;
  final Future<ChapterResponse> Function(int seriesId) loadChapter;
  final ValueChanged<int>? onChapterOpened;
  final bool fullScreenOnInit;

  const ComicReaderScreen({
    Key? key,
    required this.comic,
    required this.series,
    required this.chapterId,
    required this.initRank,
    required this.loadChapter,
    this.onChapterOpened,
    this.fullScreenOnInit = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen>
    with WidgetsBindingObserver {
  static const _readerSystemStatusChannel = EventChannel(
    'reader_system_status',
  );

  late ReaderType _readerType;
  late ReaderDirection _readerDirection;
  late int _chapterId;
  late int _initRank;
  late bool _readerFullScreen;
  ChapterResponse? _chapter;
  Object? _chapterError;
  StackTrace? _chapterStack;
  bool _chapterLoading = true;
  int _chapterRequest = 0;
  int _readerRevision = 0;
  bool _navigationInFlight = false;
  StreamSubscription<dynamic>? _readerSystemStatusSubscription;
  Map<String, dynamic>? _readerSystemStatus;
  Timer? _readerClockTimer;
  DateTime _readerClock = DateTime.now();

  void _subscribeReaderSystemStatus() {
    _readerSystemStatusSubscription =
        _readerSystemStatusChannel.receiveBroadcastStream().listen(
      (event) {
        if (!mounted || event is! Map) return;
        setState(() {
          _readerSystemStatus = {
            'network': event['network']?.toString() ?? 'unknown',
            'battery': (event['battery'] as num?)?.toInt() ?? -1,
            'charging': event['charging'] == true,
          };
        });
      },
      onError: (_) {},
    );
  }

  /// Preserve the server-side history behavior. Local page progress is written
  /// exclusively by the mounted reader after its starting index is validated.
  Future<void> _recordServerHistory() async {
    final comicId = widget.comic.id;
    try {
      if (currentIgnoreVewLog()) {
        await methods.album(comicId);
      }
    } catch (error, stackTrace) {
      debugPrient(
          "server history failed: ${error.runtimeType}/${stackTrace.runtimeType}");
    }
  }

  Future<ChapterResponse> _loadChapter(int chapterId) {
    // A custom offline loader may throw before returning a Future. Normalize
    // that case into FutureBuilder's error path instead of failing initState
    // or a setState callback synchronously.
    return Future<ChapterResponse>.sync(
      () => widget.loadChapter(chapterId),
    );
  }

  Future<void> _completeChapterLoad({
    required int targetId,
    required int revision,
    required bool preserveCurrent,
    required bool resetPosition,
  }) async {
    try {
      final chapter = await _loadChapter(targetId);
      if (!mounted || revision != _chapterRequest) return;
      setState(() {
        _chapterId = targetId;
        _chapter = chapter;
        if (resetPosition) _initRank = 0;
        _chapterError = null;
        _chapterStack = null;
        _chapterLoading = false;
        _readerRevision++;
      });
      widget.onChapterOpened?.call(targetId);
    } catch (error, stackTrace) {
      if (!mounted || revision != _chapterRequest) return;
      setState(() {
        if (!preserveCurrent) _chapter = null;
        _chapterError = error;
        _chapterStack = stackTrace;
        _chapterLoading = false;
      });
      if (preserveCurrent && _chapter != null) {
        defaultToast(
          context,
          context.l10n.tr('章节加载失败', en: 'Failed to load chapter'),
        );
      }
    }
  }

  void _load() {
    if (!mounted) {
      return;
    }
    final revision = ++_chapterRequest;
    setState(() {
      _readerType = currentReaderType;
      _readerDirection = currentReaderDirection;
      _chapter = null;
      _chapterError = null;
      _chapterStack = null;
      _chapterLoading = true;
    });
    unawaited(_completeChapterLoad(
      targetId: _chapterId,
      revision: revision,
      preserveCurrent: false,
      resetPosition: false,
    ));
  }

  Future<void> _changeChapter(int chapterId, bool fullScreen) async {
    if (!mounted || _navigationInFlight) {
      return;
    }
    _navigationInFlight = true;
    final revision = ++_chapterRequest;
    setState(() {
      _readerType = currentReaderType;
      _readerDirection = currentReaderDirection;
      _readerFullScreen = fullScreen;
      _chapterError = null;
      _chapterStack = null;
      _chapterLoading = true;
    });
    try {
      await _completeChapterLoad(
        targetId: chapterId,
        revision: revision,
        preserveCurrent: true,
        resetPosition: true,
      );
    } finally {
      _navigationInFlight = false;
    }
  }

  void _reloadReader(int initRank, bool fullScreen) {
    if (!mounted) return;
    setState(() {
      _readerType = currentReaderType;
      _readerDirection = currentReaderDirection;
      _initRank = initRank;
      _readerFullScreen = fullScreen;
      _readerRevision++;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readerType = currentReaderType;
    _readerDirection = currentReaderDirection;
    _chapterId = widget.chapterId;
    _initRank = widget.initRank;
    _readerFullScreen = widget.fullScreenOnInit;
    final revision = ++_chapterRequest;
    unawaited(_completeChapterLoad(
      targetId: _chapterId,
      revision: revision,
      preserveCurrent: false,
      resetPosition: false,
    ));
    if (Platform.isAndroid || Platform.isIOS) {
      _subscribeReaderSystemStatus();
    }
    _readerClockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() => _readerClock = DateTime.now());
      },
    );
    unawaited(_recordServerHistory());
  }

  @override
  void dispose() {
    _readerClockTimer?.cancel();
    unawaited(_readerSystemStatusSubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ComicReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterId != widget.chapterId ||
        oldWidget.comic.id != widget.comic.id) {
      // A parent may reuse this State instead of pushing a replacement route.
      // Reset the in-place chapter request so stale results cannot replace the
      // newly selected chapter.
      _readerType = currentReaderType;
      _readerDirection = currentReaderDirection;
      _chapterId = widget.chapterId;
      _initRank = widget.initRank;
      _readerFullScreen = widget.fullScreenOnInit;
      _chapter = null;
      _chapterError = null;
      _chapterStack = null;
      _chapterLoading = true;
      final revision = ++_chapterRequest;
      unawaited(_completeChapterLoad(
        targetId: _chapterId,
        revision: revision,
        preserveCurrent: false,
        resetPosition: true,
      ));
      unawaited(_recordServerHistory());
    }
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final chapter = _chapter;
    if (chapter == null && _chapterError != null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton()),
        body: ContentError(
          onRefresh: () async {
            if (!mounted) {
              return;
            }
            // 阅读器可能来自在线漫画或本地下载，重试必须沿用注入的章节加载器。
            _load();
          },
          error: _chapterError,
          stackTrace: _chapterStack,
        ),
      );
    }
    if (chapter == null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton()),
        body: const ContentLoading(),
      );
    }
    final imageCount = chapter.images.length;
    if (imageCount == 0) {
      // Do not construct any reader implementation for an empty chapter:
      // Gallery/PhotoView controllers may assert on an empty page list,
      // while list readers have no meaningful page to restore.
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton()),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.noContentAvailable),
              TextButton(
                onPressed: _load,
                child: Text(context.l10n.tr('重试', en: 'Retry')),
              ),
            ],
          ),
        ),
      );
    }
    final safeStartIndex = _initRank.clamp(0, imageCount - 1).toInt();
    final screen = Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _ComicReader(
              comicId: widget.comic.id,
              chapter: chapter,
              fallbackSeries: widget.series,
              loadChapter: _loadChapter,
              startIndex: safeStartIndex,
              key: ValueKey(
                'reader_${widget.comic.id}_${chapter.id}_$_readerType'
                '_${_readerDirection}_${_readerFullScreen}_$safeStartIndex'
                '_$_readerRevision',
              ),
              reload: _reloadReader,
              onChangeEp: _changeChapter,
              onChapterOpened: widget.onChapterOpened,
              readerType: _readerType,
              readerDirection: _readerDirection,
              fullScreenOnInit: _readerFullScreen,
              systemStatus: _readerSystemStatus,
              readerClock: _readerClock,
            ),
          ),
          if (_chapterLoading)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    key: const ValueKey('reader-chapter-loading'),
                    width: 44,
                    height: 44,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return readerKeyboardHolder(screen);
  }
}

////////////////////////////////

// Android only.
// Listen to hardware volume keys and map them to reader controls.
// Only the latest listener is active.
// Event values may be DOWN/UP.

var _volumeListenCount = 0;

void _onVolumeEvent(dynamic args) {
  _readerControllerEvent.broadcast(_ReaderControllerEventArgs("$args"));
}

EventChannel volumeButtonChannel = const EventChannel("volume_button");
StreamSubscription? volumeS;

void addVolumeListen() {
  if (!Platform.isAndroid) {
    return;
  }
  _volumeListenCount++;
  if (_volumeListenCount == 1) {
    volumeS =
        volumeButtonChannel.receiveBroadcastStream().listen(_onVolumeEvent);
  }
}

void delVolumeListen() {
  if (!Platform.isAndroid || _volumeListenCount <= 0) {
    return;
  }
  _volumeListenCount--;
  if (_volumeListenCount == 0) {
    final subscription = volumeS;
    volumeS = null;
    subscription?.cancel();
  }
}

Widget readerKeyboardHolder(Widget widget) {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return _ReaderKeyboardHolder(child: widget);
  }
  return widget;
}

class _ReaderKeyboardHolder extends StatefulWidget {
  final Widget child;

  const _ReaderKeyboardHolder({required this.child, Key? key})
      : super(key: key);

  @override
  State<_ReaderKeyboardHolder> createState() => _ReaderKeyboardHolderState();
}

class _ReaderKeyboardHolderState extends State<_ReaderKeyboardHolder> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'comic-reader-keyboard');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      child: widget.child,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _readerControllerEvent.broadcast(_ReaderControllerEventArgs("UP"));
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _readerControllerEvent
                .broadcast(_ReaderControllerEventArgs("DOWN"));
          }
        }
      },
    );
  }
}

////////////////////////////////

Event<_ReaderControllerEventArgs> _readerControllerEvent =
    Event<_ReaderControllerEventArgs>();

List<Series> _sortReaderSeries(Iterable<Series> source) {
  final indexed = source.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final aSort = int.tryParse(a.value.sort.trim());
    final bSort = int.tryParse(b.value.sort.trim());
    if (aSort != null && bSort != null) {
      final result = aSort.compareTo(bSort);
      if (result != 0) {
        return result;
      }
    } else if (aSort != null) {
      return -1;
    } else if (bSort != null) {
      return 1;
    } else {
      final result = a.value.sort.trim().compareTo(b.value.sort.trim());
      if (result != 0) {
        return result;
      }
    }
    // Keep duplicate/invalid sort values deterministic without changing the
    // server-provided order unnecessarily.
    return a.key.compareTo(b.key);
  });
  return indexed.map((entry) => entry.value).toList(growable: false);
}

class _ReaderControllerEventArgs extends EventArgs {
  final String key;

  _ReaderControllerEventArgs(this.key);
}

class _ReaderChapterData {
  _ReaderChapterData({
    required this.chapter,
    required this.pages,
  });

  final ChapterResponse chapter;
  final List<PageDescriptor> pages;
}

class _ReaderPageRef {
  const _ReaderPageRef({
    required this.chapter,
    required this.chapterPageIndex,
    required this.page,
  });

  final _ReaderChapterData chapter;
  final int chapterPageIndex;
  final PageDescriptor page;
}

class _ComicReader extends StatefulWidget {
  final int comicId;
  final ChapterResponse chapter;
  final List<Series> fallbackSeries;
  final Future<ChapterResponse> Function(int chapterId) loadChapter;
  final FutureOr Function(int, bool) reload;
  final FutureOr Function(int, bool) onChangeEp;
  final ValueChanged<int>? onChapterOpened;
  final int startIndex;
  final ReaderType readerType;
  final ReaderDirection readerDirection;
  final bool fullScreenOnInit;
  final Map<String, dynamic>? systemStatus;
  final DateTime? readerClock;

  const _ComicReader({
    required this.comicId,
    required this.chapter,
    this.fallbackSeries = const [],
    required this.loadChapter,
    required this.reload,
    required this.onChangeEp,
    this.onChapterOpened,
    required this.startIndex,
    required this.readerType,
    required this.readerDirection,
    required this.fullScreenOnInit,
    this.systemStatus,
    this.readerClock,
    Key? key,
  }) : super(key: key);

  @override
  // ignore: no_logic_in_create_state
  State<StatefulWidget> createState() {
    switch (readerType) {
      case ReaderType.webtoon:
        return _ContinuousReaderState();
      case ReaderType.gallery:
        return _PagedReaderState();
      case ReaderType.webToonFreeZoom:
        return _ContinuousReaderState();
      case ReaderType.twoPageGallery:
        return _PagedReaderState();
    }
  }
}

/// 组件回归测试直接挂载实际阅读器，省去外层章节网络请求和导航路由。
@visibleForTesting
Widget buildComicReaderForTest({
  required GlobalKey key,
  required ChapterResponse chapter,
  required ReaderType readerType,
  required ReaderDirection direction,
  List<Series> fallbackSeries = const [],
  Future<ChapterResponse> Function(int chapterId)? loadChapter,
  ValueChanged<int>? onChapterOpened,
  int startIndex = 0,
}) =>
    _ComicReader(
      key: key,
      comicId: chapter.id,
      chapter: chapter,
      fallbackSeries: fallbackSeries,
      loadChapter: loadChapter ?? (_) async => chapter,
      onChapterOpened: onChapterOpened,
      startIndex: startIndex,
      readerType: readerType,
      readerDirection: direction,
      fullScreenOnInit: false,
      reload: (_, __) {},
      onChangeEp: (_, __) {},
    );

/// 测试驱动与键盘/音量键相同的跳页入口，验证真实动画产生的中间页回调。
@visibleForTesting
void jumpComicReaderForTest(GlobalKey key, int index, {bool animation = true}) {
  (key.currentState! as _ComicReaderState)._needJumpTo(index, animation);
}

@visibleForTesting
void controlComicReaderForTest(String direction) {
  _readerControllerEvent.broadcast(_ReaderControllerEventArgs(direction));
}

@visibleForTesting
PageImageProvider comicReaderVisibleProviderForTest(
  GlobalKey key,
  int index,
) =>
    (key.currentState! as _ComicReaderState)._readerVisibleProvider(index);

@visibleForTesting
PageImageProvider comicReaderPreloadProviderForTest(
  GlobalKey key,
  int index,
) =>
    (key.currentState! as _ComicReaderState)._readerPreloadProvider(index);

@visibleForTesting
({int current, int slider, int? jumpTarget}) comicReaderProgressForTest(
    GlobalKey key) {
  final state = key.currentState! as _ComicReaderState;
  return (
    current: state._current,
    slider: state._slider,
    jumpTarget: state._jumpTarget
  );
}

abstract class _ComicReaderState extends State<_ComicReader>
    with WidgetsBindingObserver {
  static const double _bottomControlsHeight = 58;

  late ReaderPosition _position;
  late ReaderProgressWriter _progressWriter;
  late bool _fullScreen;
  ReaderSystemUiLease? _systemUiLease;
  bool _didAddVolumeListen = false;
  bool _navigationInFlight = false;
  bool _modalInFlight = false;
  bool _repaintQueued = false;
  int _preloadRevision = 0;
  final Map<int, PageImageProvider> _providers = {};
  final Map<int, PageImageProvider> _originalProviders = {};
  final Map<int, SuperResolutionPageResult> _superResolutionResults = {};
  bool _readerSuperResolutionEnabled = false;
  bool _readerSuperResolutionPreload = false;
  final List<_ReaderChapterData> _chapters = [];
  late List<PageDescriptor> _pages;
  late List<_ReaderPageRef> _pageRefs;
  bool _nextChapterLoading = false;
  Object? _nextChapterError;
  bool _reachedLastChapter = false;
  int? _lastOpenedChapterId;

  int get _current => _position.current;
  int get _slider => _position.displayPage;
  int? get _jumpTarget => _position.target;
  _ReaderPageRef get _displayPageRef => _pageRefAt(_position.clamp(_slider));
  int get _displayChapterPageIndex => _displayPageRef.chapterPageIndex;
  int get _displayChapterPageCount => _displayPageRef.chapter.pages.length;
  bool get _doubleTapFullscreen =>
      currentReaderControllerType == ReaderControllerType.touchDouble ||
      currentReaderControllerType == ReaderControllerType.touchDoubleOnceNext;
  bool get _handlesSingleTap =>
      currentReaderControllerType == ReaderControllerType.touchOnce ||
      currentReaderControllerType == ReaderControllerType.touchDoubleOnceNext ||
      currentReaderControllerType == ReaderControllerType.threeArea;
  bool get _paired => widget.readerType == ReaderType.twoPageGallery;
  bool get _autoAppendChapters => true;
  int _normalizePage(int page) =>
      _paired ? (_position.clamp(page) ~/ 2) * 2 : _position.clamp(page);

  Widget _buildViewer();
  Future<void> _moveTo(int page, bool animation);
  int _visiblePage();

  @override
  void initState() {
    super.initState();
    final initialChapter = _buildChapterData(widget.chapter);
    _chapters.add(initialChapter);
    _pages = initialChapter.pages;
    _pageRefs = [
      for (var index = 0; index < _pages.length; index++)
        _ReaderPageRef(
          chapter: initialChapter,
          chapterPageIndex: index,
          page: _pages[index],
        ),
    ];
    _lastOpenedChapterId = widget.chapter.id;
    _position = ReaderPosition(_pages.length, widget.startIndex);
    _position.report(_normalizePage(widget.startIndex));
    _fullScreen = widget.fullScreenOnInit;
    final comicId = widget.comicId;
    _progressWriter = ReaderProgressWriter(
      comicId: comicId,
      save: (page) async {
        final ref = _pageRefAt(_position.clamp(page));
        await methods.updateViewLog(
          comicId,
          ref.chapter.chapter.id,
          ref.chapterPageIndex,
        );
      },
      onError: (error, stack) =>
          debugPrient('reader progress write failed: ${error.runtimeType}'),
    );
    WidgetsBinding.instance.addObserver(this);
    _readerControllerEvent.subscribe(_onPageControl);
    if (Platform.isAndroid && currentVolumeKeyControl()) {
      addVolumeListen();
      _didAddVolumeListen = true;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      _systemUiLease = enterReaderSystemUi(fullScreen: _fullScreen);
    }
    unawaited(_loadReaderSuperResolutionState());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _progressWriter.schedule(_current);
      _preloadAround(_current);
      _maybeAppendNextChapter();
    });
  }

  _ReaderPageRef _pageRefAt(int index) => _pageRefs[index];

  _ReaderChapterData _buildChapterData(ChapterResponse chapter) {
    final pages = chapter.offlineImages == null
        ? ReaderPageRepository.fromOnline(chapter.images)
        : ReaderPageRepository.fromOffline(chapter.offlineImages!);
    return _ReaderChapterData(chapter: chapter, pages: pages);
  }

  void _appendChapter(_ReaderChapterData data) {
    final previousLength = _pages.length;
    final previousCurrent = _position.current;
    _chapters.add(data);
    _pages = [..._pages, ...data.pages];
    _pageRefs = [
      ..._pageRefs,
      for (var index = 0; index < data.pages.length; index++)
        _ReaderPageRef(
          chapter: data,
          chapterPageIndex: index,
          page: data.pages[index],
        ),
    ];
    _position = ReaderPosition(_pages.length, previousCurrent);
    _nextChapterError = null;
    _reachedLastChapter = false;
    _onPagesAppended(previousLength);
  }

  void _onPagesAppended(int previousLength) {}
  void _onPageCachePruned(Set<int> indices) {}

  List<Series> _seriesFor(_ReaderChapterData data) =>
      data.chapter.series.isEmpty ? widget.fallbackSeries : data.chapter.series;

  int? _nextChapterIdFor(_ReaderChapterData data) {
    final entries = _sortReaderSeries(_seriesFor(data));
    final index = entries.indexWhere(
      (entry) => entry.id == data.chapter.id,
    );
    return index >= 0 && index + 1 < entries.length
        ? entries[index + 1].id
        : null;
  }

  _ReaderChapterData get _currentChapter =>
      _pageRefAt(_position.navigationPage).chapter;

  Future<void> _maybeAppendNextChapter({bool force = false}) async {
    if (!_autoAppendChapters ||
        _nextChapterLoading ||
        _reachedLastChapter ||
        (!force && _current < _pages.length - 4)) {
      return;
    }
    final nextId = _nextChapterIdFor(_currentChapter);
    if (nextId == null) {
      if (mounted) setState(() => _reachedLastChapter = true);
      return;
    }
    if (_chapters.any((entry) => entry.chapter.id == nextId)) return;

    setState(() {
      _nextChapterLoading = true;
      _nextChapterError = null;
    });
    try {
      var targetId = nextId;
      _ReaderChapterData? loaded;
      final visited = <int>{};
      while (visited.add(targetId)) {
        final chapter = await widget.loadChapter(targetId);
        if (!mounted) return;
        final data = _buildChapterData(chapter);
        if (data.pages.isNotEmpty) {
          loaded = data;
          break;
        }
        final followingId = _nextChapterIdFor(data);
        if (followingId == null) break;
        targetId = followingId;
      }
      if (!mounted) return;
      if (loaded == null) {
        setState(() => _reachedLastChapter = true);
        return;
      }
      setState(() => _appendChapter(loaded!));
      _preloadAround(_current);
    } catch (error, stack) {
      if (!mounted) return;
      debugPrient(
        'reader next chapter append failed: '
        '${error.runtimeType}/${stack.runtimeType}',
      );
      setState(() => _nextChapterError = error);
    } finally {
      if (mounted) setState(() => _nextChapterLoading = false);
    }
  }

  Future<void> _loadReaderSuperResolutionState() async {
    await loadSuperResolutionState();
    if (!mounted) return;
    setState(() {
      _readerSuperResolutionEnabled = superResolutionEnabled;
      _readerSuperResolutionPreload = currentSuperResolutionPreload;
    });
  }

  PageImageProvider _readerPageProvider(int index) =>
      _pageProvider(index, superResolution: true);

  PageImageProvider _readerVisibleProvider(int index) => _pageProvider(
        index,
        superResolution: _readerSuperResolutionEnabled,
      );

  PageImageProvider _readerPreloadProvider(int index) => _pageProvider(
        index,
        superResolution:
            _readerSuperResolutionEnabled && _readerSuperResolutionPreload,
      );

  PageImageProvider _pageProvider(
    int index, {
    required bool superResolution,
  }) {
    final cache = superResolution ? _providers : _originalProviders;
    return cache.putIfAbsent(index, () {
      final ref = _pageRefAt(index);
      final page = ref.page;
      return PageImageProvider(ref.chapter.chapter.id, page.name,
          pageIndex: page.sourceIndex,
          localPath: page.localAvailable ? page.localPath : null,
          localOnly: page.localPath != null,
          superResolution: superResolution,
          onSuperResolutionResolved: superResolution
              ? (result) {
                  if (!mounted) return;
                  final previous = _superResolutionResults[index];
                  if (previous?.displayPath == result.displayPath &&
                      previous?.upscaled == result.upscaled) {
                    return;
                  }
                  _superResolutionResults[index] = result;
                  _repaint();
                }
              : null);
    });
  }

  void _showSuperResolutionComparison(int index) {
    final result = _superResolutionResults[index];
    if (result == null || !result.upscaled) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => _SuperResolutionComparisonDialog(
          pageNumber: _pageRefAt(index).chapterPageIndex + 1,
          result: result,
        ),
      ),
    );
  }

  void _preloadAround(int page) {
    final revision = ++_preloadRevision;
    final indices = readerPreloadIndices(
      current: page,
      total: _pages.length,
      pages: currentReaderPreloadPages,
      paired: _paired,
      forwardOnly: currentReaderPreloadForwardOnly,
    );
    if (indices.isEmpty) return;

    Future<void> run() async {
      for (var offset = 0; offset < indices.length; offset += 2) {
        final chunk = indices.sublist(
          offset,
          min(offset + 2, indices.length),
        );
        await Future.wait(
          chunk.map((index) async {
            if (!mounted || revision != _preloadRevision) return;
            final provider = _readerPreloadProvider(index);
            await precacheImage(provider, context, onError: (_, __) {});
            if (!mounted) {
              imageCache.evict(provider, includeLive: true);
            }
          }),
        );
        if (!mounted || revision != _preloadRevision) {
          return;
        }
      }
    }

    unawaited(run().catchError((Object error, StackTrace stack) {
      debugPrient('reader preload failed: ${error.runtimeType}');
    }));
  }

  void _repaint() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks ||
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.midFrameMicrotasks) {
      if (_repaintQueued) return;
      _repaintQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _repaintQueued = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _onCurrentChange(int index) {
    if (!mounted) return;
    final previousTarget = _jumpTarget;
    final changed = _position.report(index);
    if (changed) {
      _pruneDistantPageCaches(_current);
      _progressWriter.schedule(_current);
      _preloadAround(_current);
      _maybeAppendNextChapter();
      _reportCurrentChapterOpened();
    }
    if (changed || previousTarget != _jumpTarget) _repaint();
  }

  void _reportCurrentChapterOpened() {
    final chapterId = _currentChapter.chapter.id;
    if (_lastOpenedChapterId == chapterId) return;
    _lastOpenedChapterId = chapterId;
    widget.onChapterOpened?.call(chapterId);
  }

  void _pruneDistantPageCaches(int current) {
    const retainedPageRange = 24;
    bool isStale(int index) => (index - current).abs() > retainedPageRange;
    final stale = {
      ..._providers.keys.where(isStale),
      ..._originalProviders.keys.where(isStale),
    };
    if (stale.isEmpty) return;
    for (final index in stale) {
      final provider = _providers.remove(index);
      final originalProvider = _originalProviders.remove(index);
      if (provider != null) imageCache.evict(provider, includeLive: true);
      if (originalProvider != null) {
        imageCache.evict(originalProvider, includeLive: true);
      }
      _superResolutionResults.remove(index);
    }
    _onPageCachePruned(stale);
  }

  void _needJumpTo(int index, bool animation) {
    if (!mounted) return;
    final replacing = _position.target != null;
    final target = _normalizePage(index);
    final revision = _position.request(target);
    _repaint();
    // Coalesce controls issued in one frame. A newer intent is never discarded
    // by a timer, nor may an old animation completion overwrite that intent.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_position.isCurrent(revision)) return;
      try {
        await _moveTo(target, animation && !replacing && !currentNoAnimation());
        if (!mounted || !_position.isCurrent(revision)) return;
        _position.finish(revision, _visiblePage());
        _reportCurrentChapterOpened();
        _progressWriter.schedule(_current);
        _repaint();
      } catch (error) {
        if (!mounted || !_position.isCurrent(revision)) return;
        _position.cancel();
        _repaint();
        debugPrient('reader jump failed: ${error.runtimeType}');
      }
    });
  }

  void _onPageControl(_ReaderControllerEventArgs? event) {
    if (!mounted ||
        event == null ||
        _modalInFlight ||
        _navigationInFlight ||
        ModalRoute.of(context)?.isCurrent == false) return;
    final delta = event.key == 'UP'
        ? -1
        : event.key == 'DOWN'
            ? 1
            : 0;
    if (delta != 0) {
      _needJumpTo(_position.navigationPage + delta * (_paired ? 2 : 1),
          !currentNoAnimation());
    }
  }

  void _cancelJump() {
    if (_position.target == null) return;
    _position.cancel();
    _repaint();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_progressWriter.flush());
  }

  @override
  void dispose() {
    _preloadRevision++;
    _position.cancel();
    _progressWriter.schedule(_current);
    unawaited(_progressWriter.close());
    WidgetsBinding.instance.removeObserver(this);
    _readerControllerEvent.unsubscribe(_onPageControl);
    if (_didAddVolumeListen) delVolumeListen();
    unawaited(_systemUiLease?.release());
    final providers = _providers.values.toList();
    final chapters =
        _chapters.map((entry) => entry.chapter).toList(growable: false);
    void release() {
      for (final chapter in chapters) {
        for (final name in chapter.images) {
          evictPageImageMemoryCache(chapter.id, name, includeLive: true);
        }
      }
      for (final provider in providers) {
        imageCache.evict(provider, includeLive: true);
      }
    }

    // Image cache eviction is synchronous and can be expensive for long
    // chapters. Keep it off the route-pop first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      release();
      unawaited(
        methods.clearReaderPageCache().catchError((Object error) {
          debugPrient(
            'reader temporary cache cleanup failed: ${error.runtimeType}',
          );
        }),
      );
      unawaited(
        clearSuperResolutionTemporaryCache().catchError((Object error) {
          debugPrient(
            'reader super-resolution cache cleanup failed: '
            '${error.runtimeType}',
          );
        }),
      );
    });
    super.dispose();
  }

  void _toggleFullscreen() {
    if (!mounted) return;
    setState(() => _fullScreen = !_fullScreen);
    unawaited(_systemUiLease?.setFullScreen(_fullScreen).catchError((_) {}));
  }

  void _handleTap(TapUpDetails details, Size size) {
    switch (currentReaderControllerType) {
      case ReaderControllerType.touchOnce:
        _toggleFullscreen();
        break;
      case ReaderControllerType.touchDoubleOnceNext:
        _onPageControl(_ReaderControllerEventArgs('DOWN'));
        break;
      case ReaderControllerType.threeArea:
        var fraction = widget.readerDirection == ReaderDirection.topToBottom
            ? details.localPosition.dy / size.height
            : details.localPosition.dx / size.width;
        if (widget.readerDirection == ReaderDirection.rightToLeft) {
          fraction = 1 - fraction;
        }
        if (fraction < 1 / 3) {
          _onPageControl(_ReaderControllerEventArgs('UP'));
        } else if (fraction > 2 / 3) {
          _onPageControl(_ReaderControllerEventArgs('DOWN'));
        } else {
          _toggleFullscreen();
        }
        break;
      case ReaderControllerType.controller:
      case ReaderControllerType.touchDouble:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sideSlider =
        currentReaderSliderPosition != ReaderSliderPosition.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: _buildViewer()),
        Positioned(
          left: 12,
          bottom:
              (_fullScreen || sideSlider ? 12 : _bottomControlsHeight + 12) +
                  MediaQuery.paddingOf(context).bottom,
          child: IgnorePointer(
            child: _ReaderInfoBar(
              currentPage: _displayChapterPageIndex + 1,
              totalPages: _displayChapterPageCount,
              network: widget.systemStatus?['network']?.toString() ?? 'unknown',
              battery: (widget.systemStatus?['battery'] as int?) ?? -1,
              charging: widget.systemStatus?['charging'] == true,
              time: widget.readerClock ?? DateTime.now(),
            ),
          ),
        ),
        if (!_fullScreen)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              key: const ValueKey('reader-top-controls'),
              color: Colors.black.withValues(alpha: .74),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _currentChapter.chapter.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (_readerSuperResolutionEnabled) ...[
                        _ReaderSuperResolutionStatus(
                          result: _superResolutionResults[_current],
                          onPressed: _superResolutionResults[_current]
                                      ?.upscaled ==
                                  true
                              ? () => _showSuperResolutionComparison(_current)
                              : null,
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        tooltip: context.l10n.tr('章节列表', en: 'Chapters'),
                        onPressed: _onChooseEp,
                        icon: const Icon(
                          Icons.menu_book_rounded,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.tr(
                          '阅读设置',
                          en: 'Reading settings',
                        ),
                        onPressed: _onMoreSetting,
                        icon: const Icon(
                          Icons.tune_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (!_fullScreen && !sideSlider)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ColoredBox(
              key: const ValueKey('reader-bottom-controls'),
              color: const Color(0x88000000),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: _bottomControlsHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      _readerIconButton(
                        tooltip: context.l10n.tr('全屏', en: 'Full screen'),
                        icon: Icons.fullscreen_rounded,
                        onPressed: _toggleFullscreen,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildSliderWidget(Axis.horizontal),
                      ),
                      Container(
                        key: const ValueKey('reader-page-indicator'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${_displayChapterPageIndex + 1} / '
                          '$_displayChapterPageCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        if (!_fullScreen && sideSlider)
          Align(
            alignment: currentReaderSliderPosition == ReaderSliderPosition.left
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Container(
              width: 34,
              height: 280,
              decoration: BoxDecoration(
                color: const Color(0x88000000),
                borderRadius: BorderRadius.circular(18),
              ),
              child: _buildSliderWidget(Axis.vertical),
            ),
          ),
        if (currentReaderControllerType == ReaderControllerType.controller &&
            (_fullScreen || sideSlider))
          SafeArea(
              child: Align(
            alignment: Alignment.bottomLeft,
            child: _readerIconButton(
              tooltip: _fullScreen
                  ? context.l10n.tr('退出全屏', en: 'Exit full screen')
                  : context.l10n.tr('全屏', en: 'Full screen'),
              icon: _fullScreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              onPressed: _toggleFullscreen,
            ),
          )),
        if (_position.preview != null)
          IgnorePointer(
              child: Center(
                  child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xCC000000),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
            ),
            child: Text(
                '${_displayChapterPageIndex + 1} / $_displayChapterPageCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                )),
          ))),
      ]),
    );
  }

  Widget _readerIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: .08),
      ),
      icon: Icon(icon, size: 21),
    );
  }

  Widget _buildSliderWidget(Axis axis) {
    final chapterRef = _displayPageRef.chapter;
    final int chapterStart =
        _pageRefs.indexWhere((entry) => identical(entry.chapter, chapterRef));
    if (chapterRef.pages.length <= 1 || chapterStart < 0) {
      return const SizedBox.shrink();
    }
    return FlutterSlider(
      axis: axis,
      handlerWidth: 14,
      handlerHeight: 14,
      touchSize: 17,
      handler: FlutterSliderHandler(
        decoration: const BoxDecoration(),
        child: const DecoratedBox(
          key: ValueKey('reader-progress-thumb'),
          decoration:
              BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: SizedBox.expand(),
        ),
      ),
      handlerAnimation: const FlutterSliderHandlerAnimation(scale: 1),
      trackBar: FlutterSliderTrackBar(
        activeTrackBarHeight: 3,
        inactiveTrackBarHeight: 3,
        inactiveTrackBar: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.grey.shade300,
        ),
        activeTrackBar: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      values: [_displayChapterPageIndex.toDouble()],
      min: 0,
      max: (chapterRef.pages.length - 1).toDouble(),
      onDragStarted: (_, __, ___) =>
          setState(() => _position.preview = _current),
      onDragging: (_, value, __) =>
          setState(() => _position.preview = _position.clamp(
                chapterStart + (value as num).round(),
              )),
      onDragCompleted: (_, value, __) =>
          _needJumpTo(chapterStart + (value as num).round(), false),
      step: const FlutterSliderStep(step: 1, isPercentRange: false),
      tooltip: FlutterSliderTooltip(disabled: true),
    );
  }

  int? get _nextChapterId {
    return _nextChapterIdFor(_currentChapter);
  }

  Future<void> _navigate(int id) async {
    if (!mounted || _navigationInFlight) return;
    _navigationInFlight = true;
    _progressWriter.schedule(_current);
    unawaited(_progressWriter.flush());
    try {
      await widget.onChangeEp(id, _fullScreen);
    } catch (error) {
      debugPrient('reader chapter navigation failed: ${error.runtimeType}');
    } finally {
      _navigationInFlight = false;
    }
  }

  Widget _buildContinuousFooter() {
    late final Widget content;
    if (_nextChapterLoading) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.tr('正在加载', en: 'Loading'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    } else if (_nextChapterError != null) {
      content = Center(
        child: TextButton.icon(
          onPressed: () => unawaited(
            _maybeAppendNextChapter(force: true),
          ),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(
            context.l10n.tr('后续内容加载失败，点击重试', en: 'Retry loading'),
          ),
        ),
      );
    } else if (_reachedLastChapter || _nextChapterId == null) {
      content = Center(
        child: Text(
          context.l10n.tr('已经到最后了', en: 'You have reached the end'),
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    } else {
      content = Center(
        child: Text(
          context.l10n.tr(
            '继续向下滚动以加载后续内容',
            en: 'Keep scrolling to load more pages',
          ),
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        bottom: !_fullScreen &&
                currentReaderSliderPosition == ReaderSliderPosition.bottom
            ? _bottomControlsHeight + MediaQuery.viewPaddingOf(context).bottom
            : 0,
      ),
      child: content,
    );
  }

  Future<void> _onChooseEp() async {
    if (_modalInFlight || _navigationInFlight) return;
    _modalInFlight = true;
    try {
      await showMaterialModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xF21B1B1F),
        barrierColor: Colors.black.withValues(alpha: .62),
        useRootNavigator: true,
        enableDrag: true,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        builder: (sheetContext) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .62,
          child: SafeArea(
            top: false,
            child: _EpChooser(
              _currentChapter.chapter,
              (id, _) => _navigate(id),
              series: _seriesFor(_currentChapter),
            ),
          ),
        ),
      );
    } catch (error) {
      debugPrient('reader chapter chooser failed: ${error.runtimeType}');
    } finally {
      _modalInFlight = false;
    }
  }

  Future<void> _onMoreSetting() async {
    if (_modalInFlight || _navigationInFlight) return;
    _modalInFlight = true;
    try {
      await showMaterialModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xF21B1B1F),
        barrierColor: Colors.black.withValues(alpha: .62),
        useRootNavigator: true,
        enableDrag: true,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        builder: (sheetContext) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .48,
          child: SafeArea(
            top: false,
            child: _SettingPanel(),
          ),
        ),
      );
    } catch (error) {
      debugPrient('reader settings failed: ${error.runtimeType}');
      return;
    } finally {
      _modalInFlight = false;
    }
    if (!mounted) return;
    if (widget.readerDirection != currentReaderDirection ||
        widget.readerType != currentReaderType) {
      _progressWriter.schedule(_current);
      unawaited(_progressWriter.flush());
      await widget.reload(_current, _fullScreen);
    } else {
      setState(() {});
    }
  }
}

class _ReaderInfoBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final String network;
  final int battery;
  final bool charging;
  final DateTime time;

  const _ReaderInfoBar({
    required this.currentPage,
    required this.totalPages,
    required this.network,
    required this.battery,
    required this.charging,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final percent = totalPages <= 0
        ? 0
        : ((currentPage / totalPages) * 100).round().clamp(0, 100);
    final networkInfo = switch (network) {
      'wifi' => (Icons.wifi_rounded, context.l10n.tr('WLAN', en: 'Wi-Fi')),
      'mobile' => (
          Icons.signal_cellular_alt_rounded,
          context.l10n.tr('移动', en: 'Mobile'),
        ),
      'ethernet' => (Icons.lan_rounded, context.l10n.tr('有线', en: 'Ethernet')),
      'vpn' => (Icons.vpn_lock_rounded, context.l10n.tr('VPN', en: 'VPN')),
      'bluetooth' => (
          Icons.bluetooth_rounded,
          context.l10n.tr('蓝牙', en: 'Bluetooth'),
        ),
      'offline' => (
          Icons.wifi_off_rounded,
          context.l10n.tr('离线', en: 'Offline'),
        ),
      _ => (Icons.language_rounded, context.l10n.tr('网络', en: 'Network')),
    };
    final batteryColor = battery >= 0 && battery <= 20
        ? const Color(0xFFFF7373)
        : const Color(0xFFD8DCE3);
    final clock = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    const radius = BorderRadius.all(Radius.circular(12));
    return ClipRRect(
      key: const ValueKey('reader-info-bar'),
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .28),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: .16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: 13,
                color: Colors.white70,
              ),
              const SizedBox(width: 3),
              Text(
                '$currentPage/$totalPages · $percent%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const _InfoBarDivider(),
              Icon(
                networkInfo.$1,
                size: 13,
                color: Colors.white70,
                semanticLabel: networkInfo.$2,
              ),
              if (network != 'wifi') ...[
                const SizedBox(width: 2),
                Text(
                  networkInfo.$2,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
              const _InfoBarDivider(),
              Icon(
                charging
                    ? Icons.battery_charging_full_rounded
                    : Icons.battery_full_rounded,
                size: 14,
                color: batteryColor,
              ),
              const SizedBox(width: 1),
              Text(
                battery < 0 ? '--' : '$battery%',
                style: TextStyle(
                  color: batteryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const _InfoBarDivider(),
              Icon(Icons.schedule_rounded, size: 13, color: Colors.white70),
              const SizedBox(width: 2),
              Text(
                clock,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBarDivider extends StatelessWidget {
  const _InfoBarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: .18),
    );
  }
}

class _ReaderSuperResolutionStatus extends StatelessWidget {
  final SuperResolutionPageResult? result;
  final VoidCallback? onPressed;

  const _ReaderSuperResolutionStatus({
    required this.result,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final active = result?.upscaled;
    final color =
        active == true ? const Color(0xFF7EE7F4) : const Color(0xFFB8BCC4);
    final text = active == null
        ? context.l10n.tr('2× 处理中', en: '2× working')
        : active
            ? context.l10n.tr('2× 已生效', en: '2× active')
            : context.l10n.tr('原图', en: 'Original');
    final tooltip = active == true
        ? context.l10n.tr(
            '超分已生效，点击对比原图',
            en: 'Upscaling active; tap to compare',
          )
        : active == false
            ? context.l10n.tr(
                '当前页超分未生效，正在显示原图',
                en: 'Upscaling unavailable; showing the original',
              )
            : context.l10n.tr(
                '正在处理 2× 超分',
                en: 'Preparing 2× upscaling',
              );
    return Tooltip(
      message: tooltip,
      child: Material(
        key: const ValueKey('reader-super-resolution-status'),
        color: Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active != null)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  Icon(Icons.hourglass_top_rounded, size: 12, color: color),
                const SizedBox(width: 5),
                Text(
                  text,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _SuperResolutionComparisonDialog extends StatefulWidget {
  final int pageNumber;
  final SuperResolutionPageResult result;

  const _SuperResolutionComparisonDialog({
    required this.pageNumber,
    required this.result,
  });

  @override
  State<_SuperResolutionComparisonDialog> createState() =>
      _SuperResolutionComparisonDialogState();
}

class _SuperResolutionComparisonDialogState
    extends State<_SuperResolutionComparisonDialog> {
  bool _showUpscaled = true;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final path =
        _showUpscaled ? widget.result.displayPath : widget.result.sourcePath;
    return Dialog(
      key: const ValueKey('reader-super-resolution-comparison'),
      insetPadding: const EdgeInsets.all(14),
      clipBehavior: Clip.antiAlias,
      backgroundColor: const Color(0xF21B1B1F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: min(size.width - 28, 900),
        height: size.height * .84,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.tr(
                        '超分对比 · 第 ${widget.pageNumber} 页',
                        en: 'Upscaling comparison · Page ${widget.pageNumber}',
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.tr('关闭', en: 'Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      key: const ValueKey(
                        'reader-super-resolution-comparison-mode',
                      ),
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(
                            context.l10n.tr('原图', en: 'Original'),
                          ),
                          icon: const Icon(Icons.image_outlined),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(
                            context.l10n.tr('2× 超分', en: '2× upscaled'),
                          ),
                          icon: const Icon(Icons.auto_awesome_rounded),
                        ),
                      ],
                      selected: {_showUpscaled},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        setState(() => _showUpscaled = selection.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: LayoutBuilder(
                  builder: (context, constraints) => InteractiveViewer(
                    minScale: .6,
                    maxScale: 8,
                    boundaryMargin: const EdgeInsets.all(120),
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: Image.file(
                        File(path),
                        key: ValueKey(path),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                            context.l10n.tr(
                              '对比图片加载失败',
                              en: 'Unable to load comparison image',
                            ),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
              child: Text(
                context.l10n.tr(
                  '切换模式后可双指缩放查看文字和线条细节。',
                  en: 'Switch modes and pinch to inspect text and line details.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
