import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/super_resolution_models.dart';

const _superResolutionPropertyName = 'reader_super_resolution_v1';

bool _enabledPreference = false;
InstalledSuperResolutionModel? _installedModel;
Future<void>? _loading;
bool _loaded = false;
final Map<String, Future<String>> _superResolutionPathCache = {};

bool get superResolutionEnabled =>
    _enabledPreference && _installedModel != null;

bool get superResolutionModelInstalled => _installedModel != null;

String? get superResolutionModelDirectory => _installedModel?.directory.path;

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
      methods.getHomeDir(),
    ]);
    final preference = values[0].trim().toLowerCase() == 'true';
    final model = await findInstalledSuperResolutionModel(values[1]);
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

Future<void> setSuperResolutionEnabled(bool enabled) async {
  await loadSuperResolutionState();
  if (enabled && _installedModel == null) {
    throw StateError('super-resolution model is not installed');
  }
  await methods.saveProperty(_superResolutionPropertyName, '$enabled');
  _enabledPreference = enabled;
  invalidateSuperResolutionCache();
}

Future<String> superResolutionPagePath(String sourcePath) async {
  await loadSuperResolutionState();
  final model = _installedModel;
  if (!_enabledPreference || model == null) return sourcePath;
  final source = File(sourcePath);
  final key = '${model.directory.path}|${model.version}|'
      '${source.path}|${source.lengthSync()}|${source.lastModifiedSync().microsecondsSinceEpoch}';
  final existing = _superResolutionPathCache[key];
  if (existing != null) return existing;
  late final Future<String> future;
  future = methods
      .superResolutionImage(
    inputPath: sourcePath,
    modelDirectory: model.directory.path,
  )
      .catchError((Object error, StackTrace stack) {
    if (identical(_superResolutionPathCache[key], future)) {
      _superResolutionPathCache.remove(key);
    }
    debugPrient('super-resolution fallback: ${error.runtimeType}');
    return sourcePath;
  });
  _superResolutionPathCache[key] = future;
  return future;
}

void invalidateSuperResolutionCache() {
  _superResolutionPathCache.clear();
  imageCache.clear();
  imageCache.clearLiveImages();
}

Future<void> clearSuperResolutionTemporaryCache() async {
  _superResolutionPathCache.clear();
  await methods.clearSuperResolutionCache();
}
