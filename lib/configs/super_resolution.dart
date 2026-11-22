import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/super_resolution_models.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _superResolutionPropertyName = 'reader_super_resolution_v1';
const _superResolutionThreadsPropertyName =
    'reader_super_resolution_threads_v1';
const _superResolutionTilePropertyName = 'reader_super_resolution_tile_v1';
const _superResolutionPreloadPropertyName =
    'reader_super_resolution_preload_v1';
const superResolutionFeatureAvailable = false;

bool _enabledPreference = false;
int _selectedThreads = 0;
int _selectedTileSize = 384;
bool _preloadEnabled = false;
InstalledSuperResolutionModel? _installedModel;
Future<void>? _loading;
bool _loaded = false;
final Map<String, Future<SuperResolutionPageResult>> _superResolutionPathCache =
    {};

class SuperResolutionPageResult {
  final String sourcePath;
  final String displayPath;
  final bool upscaled;
  final String? failureReason;

  const SuperResolutionPageResult({
    required this.sourcePath,
    required this.displayPath,
    required this.upscaled,
    this.failureReason,
  });
}

bool get superResolutionEnabled =>
    superResolutionFeatureAvailable &&
    _enabledPreference &&
    _installedModel != null;

bool get superResolutionModelInstalled => _installedModel != null;

String? get superResolutionModelDirectory => _installedModel?.directory.path;

int get currentSuperResolutionThreads {
  if (_selectedThreads > 0) return _selectedThreads;
  return (Platform.numberOfProcessors - 1).clamp(2, 6).toInt();
}

int get currentSuperResolutionTileSize => _selectedTileSize;

bool get currentSuperResolutionPreload => _preloadEnabled;

Future<void> loadSuperResolutionState({bool force = false}) {
  if (_loaded && !force) return Future.value();
  if (_loading != null && !force) return _loading!;
  final future = _loadSuperResolutionState();
  _loading = future;
  return future.whenComplete(() {
    if (identical(_loading, future)) _loading = null;
  });
}

Future<void> _loadSuperResolutionState() async {
  try {
    final values = await Future.wait([
      methods.loadProperty(_superResolutionPropertyName),
      methods.loadProperty(_superResolutionThreadsPropertyName),
      methods.loadProperty(_superResolutionTilePropertyName),
      methods.loadProperty(_superResolutionPreloadPropertyName),
      methods.getHomeDir(),
    ]);
    final preference = values[0].trim().toLowerCase() == 'true';
    _selectedThreads = _parseThreads(values[1]);
    _selectedTileSize = _parseTileSize(values[2]);
    _preloadEnabled = values[3].trim().toLowerCase() == 'true';
    final model = await findInstalledSuperResolutionModel(values[4]);
    _enabledPreference = preference;
    _installedModel = model;
    _loaded = true;
  } catch (error) {
    debugPrient('super-resolution state load failed: ${error.runtimeType}');
    _enabledPreference = false;
    _installedModel = null;
    _loaded = false;
  }
}

int _parseThreads(String raw) {
  final value = int.tryParse(raw.trim()) ?? 0;
  return const {0, 2, 4, 6, 8}.contains(value) ? value : 0;
}

int _parseTileSize(String raw) {
  final value = int.tryParse(raw.trim()) ?? 384;
  return const {128, 256, 384}.contains(value) ? value : 384;
}

Future<void> setSuperResolutionEnabled(bool enabled) async {
  await loadSuperResolutionState();
  if (enabled && _installedModel == null) {
    throw StateError('super-resolution model is not installed');
  }
  await methods.saveProperty(_superResolutionPropertyName, '$enabled');
  _enabledPreference = enabled;
  invalidateSuperResolutionCache();
}

Future<void> setSuperResolutionThreads(int value) async {
  final normalized = const {0, 2, 4, 6, 8}.contains(value) ? value : 0;
  await methods.saveProperty(
    _superResolutionThreadsPropertyName,
    '$normalized',
  );
  _selectedThreads = normalized;
}

Future<void> setSuperResolutionTileSize(int value) async {
  final normalized = const {128, 256, 384}.contains(value) ? value : 256;
  await methods.saveProperty(
    _superResolutionTilePropertyName,
    '$normalized',
  );
  _selectedTileSize = normalized;
  invalidateSuperResolutionCache();
}

Future<void> setSuperResolutionPreloadEnabled(bool enabled) async {
  await methods.saveProperty(_superResolutionPreloadPropertyName, '$enabled');
  _preloadEnabled = enabled;
}

String superResolutionThreadsName(BuildContext context) {
  if (_selectedThreads == 0) {
    return context.l10n.tr(
      '自动（$currentSuperResolutionThreads 线程）',
      en: 'Auto ($currentSuperResolutionThreads threads)',
    );
  }
  return context.l10n.tr(
    '$_selectedThreads 线程',
    en: '$_selectedThreads threads',
  );
}

String superResolutionTileName(BuildContext context) {
  return switch (_selectedTileSize) {
    128 => context.l10n.tr('低内存 · 128', en: 'Low memory · 128'),
    384 => context.l10n.tr('高速 · 384', en: 'Fast · 384'),
    _ => context.l10n.tr('均衡 · 256', en: 'Balanced · 256'),
  };
}

Future<bool> chooseSuperResolutionThreads(BuildContext context) async {
  final selected = await chooseMapDialog<int>(
    context,
    title: context.l10n.tr('超分推理线程', en: 'Upscaling threads'),
    values: {
      for (final value in const [0, 2, 4, 6, 8])
        value == 0
            ? context.l10n.tr(
                '自动（${(Platform.numberOfProcessors - 1).clamp(2, 6)} 线程）',
                en: 'Auto (${(Platform.numberOfProcessors - 1).clamp(2, 6)} threads)',
              )
            : context.l10n.tr('$value 线程', en: '$value threads'): value,
    },
  );
  if (selected == null) return false;
  await setSuperResolutionThreads(selected);
  return true;
}

Future<bool> chooseSuperResolutionTileSize(BuildContext context) async {
  final selected = await chooseMapDialog<int>(
    context,
    title: context.l10n.tr('超分分块大小', en: 'Upscaling tile size'),
    values: {
      context.l10n.tr('低内存 · 128', en: 'Low memory · 128'): 128,
      context.l10n.tr('均衡 · 256', en: 'Balanced · 256'): 256,
      context.l10n.tr('高速 · 384', en: 'Fast · 384'): 384,
    },
  );
  if (selected == null) return false;
  await setSuperResolutionTileSize(selected);
  return true;
}

Future<SuperResolutionPageResult> superResolutionPageResult(
  String sourcePath,
) async {
  await loadSuperResolutionState();
  final model = _installedModel;
  if (!_enabledPreference || model == null) {
    return SuperResolutionPageResult(
      sourcePath: sourcePath,
      displayPath: sourcePath,
      upscaled: false,
      failureReason: model == null
          ? 'super-resolution model is not installed'
          : 'super-resolution is disabled',
    );
  }
  final source = File(sourcePath);
  final key = '${model.directory.path}|${model.version}|'
      '${source.path}|${source.lengthSync()}|${source.lastModifiedSync().microsecondsSinceEpoch}';
  final existing = _superResolutionPathCache[key];
  if (existing != null) {
    return existing;
  }
  late final Future<SuperResolutionPageResult> future;
  future = methods
      .superResolutionImage(
        inputPath: sourcePath,
        modelDirectory: model.directory.path,
        threads: currentSuperResolutionThreads,
        tileSize: currentSuperResolutionTileSize,
      )
      .then(
        (displayPath) => SuperResolutionPageResult(
          sourcePath: sourcePath,
          displayPath: displayPath,
          upscaled: displayPath != sourcePath,
        ),
      )
      .catchError((Object error, StackTrace stack) {
    if (identical(_superResolutionPathCache[key], future)) {
      _superResolutionPathCache.remove(key);
    }
    debugPrient('super-resolution fallback: ${error.runtimeType}');
    return SuperResolutionPageResult(
      sourcePath: sourcePath,
      displayPath: sourcePath,
      upscaled: false,
      failureReason: '$error',
    );
  });
  _superResolutionPathCache[key] = future;
  return future;
}

Future<String> superResolutionPagePath(String sourcePath) async =>
    (await superResolutionPageResult(sourcePath)).displayPath;

void invalidateSuperResolutionCache() {
  _superResolutionPathCache.clear();
  imageCache.clear();
  imageCache.clearLiveImages();
}

Future<void> clearSuperResolutionTemporaryCache() async {
  _superResolutionPathCache.clear();
  await methods.clearSuperResolutionCache();
}
