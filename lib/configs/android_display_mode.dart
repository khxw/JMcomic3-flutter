/// Android display refresh-rate mode.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/android_version.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import 'string_property.dart';

const _propertyName = "androidRefreshModeId";
const _legacyPropertyName = "androidDisplayMode";

List<String> _legacyModes = [];
List<AndroidRefreshModeInfo> _refreshModes = [];
int? _androidRefreshModeId;
String _legacySelectedMode = "";

class AndroidRefreshModeInfo {
  final int id;
  final int width;
  final int height;
  final double refreshRate;

  const AndroidRefreshModeInfo({
    required this.id,
    required this.width,
    required this.height,
    required this.refreshRate,
  });

  factory AndroidRefreshModeInfo.fromMap(Map<String, dynamic> map) {
    return AndroidRefreshModeInfo(
      id: _toInt(map['id']),
      width: _toInt(map['width']),
      height: _toInt(map['height']),
      refreshRate: _toDouble(map['refresh_rate']),
    );
  }

  int get pixelCount => width * height;
  int get hz => refreshRate.round();

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse("$value") ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse("$value") ?? 0;
  }
}

class AndroidRefreshRateOption {
  final int hz;
  final int? modeId;
  final String rawMode;
  final int pixelCount;

  const AndroidRefreshRateOption({
    required this.hz,
    required this.pixelCount,
    this.modeId,
    this.rawMode = '',
  });
}

Future initAndroidDisplayMode() async {
  if (!Platform.isAndroid) return;

  _refreshModes = (await methods.loadAndroidRefreshModes())
      .map(AndroidRefreshModeInfo.fromMap)
      .where((mode) => mode.id > 0 && mode.refreshRate >= 30)
      .toList(growable: false);
  _legacyModes = await methods.loadAndroidModes();

  final savedId = int.tryParse(
    parseStringPropertyValue(await methods.loadProperty(_propertyName),
        trim: true),
  );
  var selectedId =
      _refreshModes.any((mode) => mode.id == savedId) ? savedId : null;

  final legacy = normalizeAndroidDisplayModeValue(
    await methods.loadProperty(_legacyPropertyName),
    _legacyModes,
  );
  _legacySelectedMode = legacy;
  selectedId ??= _modeIdFromLegacyValue(legacy);
  _androidRefreshModeId = selectedId;

  await _changeMode();
}

String normalizeAndroidDisplayModeValue(String raw, Iterable<String> modes) {
  final value = parseStringPropertyValue(raw, trim: true);
  if (value.isEmpty) return "";
  return modes.contains(value) ? value : "";
}

int? _modeIdFromLegacyValue(String raw) {
  if (raw.isEmpty || _refreshModes.isEmpty) return null;
  final id = int.tryParse(
    RegExp(r'id\s*=\s*(\d+)').firstMatch(raw)?.group(1) ?? '',
  );
  if (id != null && _refreshModes.any((mode) => mode.id == id)) {
    return id;
  }
  final rate = parseAndroidRefreshRate(raw);
  if (rate == null) return null;
  return _bestModeAtRate(rate)?.id;
}

Future _changeMode() async {
  if (_refreshModes.isNotEmpty) {
    await methods.setAndroidRefreshMode(_androidRefreshModeId);
    return;
  }
  if (_legacySelectedMode.isNotEmpty) {
    await methods.setAndroidMode(_legacySelectedMode);
  }
}

Future<void> reapplyAndroidDisplayMode() async {
  if (Platform.isAndroid) {
    await _changeMode();
  }
}

double? parseAndroidRefreshRate(String rawMode) {
  final match =
      RegExp(r'refreshRate\s*=\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(rawMode);
  return match == null ? null : double.tryParse(match.group(1)!);
}

int _pixelsOf(String rawMode) {
  final width = int.tryParse(
      RegExp(r'width\s*=\s*(\d+)').firstMatch(rawMode)?.group(1) ?? '');
  final height = int.tryParse(
      RegExp(r'height\s*=\s*(\d+)').firstMatch(rawMode)?.group(1) ?? '');
  return (width ?? 0) * (height ?? 0);
}

List<AndroidRefreshRateOption> buildAndroidRefreshRateOptions(
  Iterable<String> modes,
) {
  final byRate = <int, AndroidRefreshRateOption>{};
  for (final mode in modes) {
    final rate = parseAndroidRefreshRate(mode);
    if (rate == null || rate < 30) continue;
    final hz = rate.round();
    final pixels = _pixelsOf(mode);
    final current = byRate[hz];
    if (current == null || pixels > current.pixelCount) {
      byRate[hz] = AndroidRefreshRateOption(
        hz: hz,
        rawMode: mode,
        pixelCount: pixels,
      );
    }
  }
  final result = byRate.values.toList()..sort((a, b) => a.hz.compareTo(b.hz));
  return result;
}

List<AndroidRefreshRateOption> buildStructuredRefreshRateOptions(
  Iterable<AndroidRefreshModeInfo> modes,
) {
  final byRate = <int, AndroidRefreshRateOption>{};
  for (final mode in modes) {
    if (mode.id <= 0 || mode.refreshRate < 30) continue;
    final current = byRate[mode.hz];
    if (current == null || mode.pixelCount > current.pixelCount) {
      byRate[mode.hz] = AndroidRefreshRateOption(
        hz: mode.hz,
        modeId: mode.id,
        pixelCount: mode.pixelCount,
      );
    }
  }
  return byRate.values.toList()..sort((a, b) => a.hz.compareTo(b.hz));
}

AndroidRefreshModeInfo? _bestModeAtRate(double rate) {
  final hz = rate.round();
  AndroidRefreshModeInfo? best;
  for (final mode in _refreshModes) {
    if (mode.hz != hz) continue;
    if (best == null || mode.pixelCount > best.pixelCount) {
      best = mode;
    }
  }
  return best;
}

AndroidRefreshModeInfo? get _selectedMode {
  final id = _androidRefreshModeId;
  if (id == null) return null;
  for (final mode in _refreshModes) {
    if (mode.id == id) return mode;
  }
  return null;
}

String _refreshRateLabel(BuildContext context) {
  final mode = _selectedMode;
  if (mode == null) {
    return context.l10n.tr('跟随系统', en: 'System default');
  }
  return '${mode.hz} Hz';
}

Future<void> _selectRefreshRate(BuildContext context, int? modeId) async {
  if (modeId != null && !_refreshModes.any((mode) => mode.id == modeId)) {
    return;
  }
  try {
    await methods.saveProperty(_propertyName, modeId?.toString() ?? "");
    _androidRefreshModeId = modeId;
    await _changeMode();
  } catch (error) {
    if (context.mounted) {
      defaultToast(
        context,
        context.l10n.tr(
          '刷新率切换失败：$error',
          en: 'Failed to change refresh rate: $error',
        ),
      );
    }
  }
}

Widget androidDisplayModeSetting() {
  if (!Platform.isAndroid || androidVersion < 23) {
    return const SizedBox.shrink();
  }
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      final options = buildStructuredRefreshRateOptions(_refreshModes);
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        key: const ValueKey('android-refresh-rate-setting'),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.speed_rounded,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.tr(
                          '屏幕刷新率',
                          en: 'Display refresh rate',
                        ),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _refreshRateLabel(context),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _selectedMode == null
                        ? context.l10n.tr('自动', en: 'Auto')
                        : _refreshRateLabel(context),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (options.isEmpty)
              Text(
                context.l10n.tr(
                  '当前设备未提供可切换的刷新率模式。',
                  en: 'This device exposes no switchable refresh-rate modes.',
                ),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('refresh-rate-default'),
                    label: Text(
                      context.l10n.tr('系统默认', en: 'System default'),
                    ),
                    selected: _androidRefreshModeId == null,
                    onSelected: (_) async {
                      await _selectRefreshRate(context, null);
                      setState(() {});
                    },
                  ),
                  for (final option in options)
                    ChoiceChip(
                      key: ValueKey('refresh-rate-${option.hz}'),
                      label: Text('${option.hz} Hz'),
                      selected: _androidRefreshModeId == option.modeId,
                      onSelected: (_) async {
                        await _selectRefreshRate(context, option.modeId);
                        setState(() {});
                      },
                    ),
                ],
              ),
          ],
        ),
      );
    },
  );
}
