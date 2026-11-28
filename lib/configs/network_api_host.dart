import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/configs/network_host.dart';
import 'package:jmcomic3/configs/network_ping.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _defaultApiHost = "www.cdngwc.club";
const _automaticProbeTimeout = Duration(milliseconds: 1500);
const _rotationFallbackTimeout = Duration(milliseconds: 2500);
const _apiRotationCooldown = Duration(seconds: 2);
const _apiFailureThreshold = 2;
const _apiCircuitDuration = Duration(minutes: 5);
const _lastSuccessfulApiHostKey = "api_host_last_success";
const _apiHostHealthKey = "api_host_health_v1";
// 动态域名拉取失败时使用内置移动端 API 候选，保持设置页和后端候选一致。
const _fallbackApiHosts = <String>[
  "www.cdnhjk.net",
  "www.cdngwc.club",
  "www.cdngwc.net",
  "www.cdngwc.cc",
  "www.cdnbea.net",
  "www.cdnhth.net",
  "www.cdnhth.club",
];
String _apiHost = _defaultApiHost;
String _lastSuccessfulApiHost = "";

List<String> _apiList = [];
Future<bool>? _apiRotationInflight;
DateTime? _lastApiRotationAttemptAt;

class _ApiHostHealth {
  int failures;
  int blockedUntilMs;

  _ApiHostHealth({
    this.failures = 0,
    this.blockedUntilMs = 0,
  });

  bool get blocked => blockedUntilMs > DateTime.now().millisecondsSinceEpoch;

  factory _ApiHostHealth.fromJson(Map<String, dynamic> json) {
    return _ApiHostHealth(
      failures: (json['failures'] as num?)?.toInt() ?? 0,
      blockedUntilMs: (json['blocked_until_ms'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'failures': failures,
        'blocked_until_ms': blockedUntilMs,
      };
}

final Map<String, _ApiHostHealth> _apiHostHealth = {};

Future<void> initApiHost() async {
  Methods.apiHostRecoveryHandler = rotateApiHostAfterInvalidResponse;
  _apiList = [];
  _apiHostHealth.clear();
  _lastApiRotationAttemptAt = null;
  _mergeApiList(_fallbackApiHosts);
  await _loadApiHostHealth();
  final hostListFuture = methods.loadApiHostList();
  final currentHostFuture = methods.loadApiHost();
  try {
    _mergeApiList(await hostListFuture);
  } catch (e) {
    debugPrient("initApiHost loadApiHostList failed: $e");
    // Keep local fallback list when backend list is unavailable.
  }
  final rawLoaded = await currentHostFuture;
  final loaded =
      normalizeApiHostCandidate(rawLoaded, fallback: _defaultApiHost);
  _apiHost = loaded;
  _mergeApiList([_apiHost]);
  var rawLastSuccess = "";
  try {
    rawLastSuccess = await methods.loadProperty(_lastSuccessfulApiHostKey);
  } catch (error) {
    debugPrient(
      "initApiHost load last success failed: ${error.runtimeType}",
    );
  }
  _lastSuccessfulApiHost =
      normalizeApiHostCandidate(rawLastSuccess, fallback: "");
  if (_lastSuccessfulApiHost.isNotEmpty) {
    _mergeApiList([_lastSuccessfulApiHost]);
  }
  if (rawLoaded.trim() != _apiHost) {
    await methods.saveApiHost(_apiHost);
  }
  await autoSelectApiHost();
}

Future<bool> rotateApiHostAfterInvalidResponse([int? observedVersion]) {
  return _rotateApiHostForRequest(observedVersion ?? Methods.apiRouteVersion);
}

Future<bool> _rotateApiHostForRequest(int observedVersion) async {
  if (Methods.apiRouteVersion != observedVersion) {
    return true;
  }
  final running = _apiRotationInflight;
  if (running != null) return running;
  final future = _performApiHostRotation();
  _apiRotationInflight = future;
  try {
    return await future;
  } finally {
    if (identical(_apiRotationInflight, future)) {
      _apiRotationInflight = null;
    }
  }
}

Future<bool> _performApiHostRotation() async {
  if (_apiList.isEmpty) return false;
  final now = DateTime.now();
  final lastAttempt = _lastApiRotationAttemptAt;
  if (lastAttempt != null &&
      now.difference(lastAttempt) < _apiRotationCooldown) {
    return false;
  }
  _lastApiRotationAttemptAt = now;
  final current = _apiHost.toLowerCase();
  final candidates = _probeableApiHosts(_apiList
      .where((host) => host.toLowerCase() != current)
      .toList(growable: false));
  if (candidates.isEmpty) return false;

  // Resolve one healthy replacement before persisting it. Sequential blind
  // switches can walk through the entire host list during a startup burst.
  var selected = await selectFastestHost(
    candidates,
    _probeApiHost,
    timeout: _automaticProbeTimeout,
  );
  selected ??= await selectFastestHost(
    candidates,
    _probeApiHost,
    timeout: _rotationFallbackTimeout,
    returnOnFirstSuccess: true,
  );
  if (selected == null) {
    debugPrient('No healthy API route found during recovery rotation');
    return false;
  }
  try {
    await methods.saveApiHost(selected.host);
    _apiHost = selected.host;
    Methods.apiRouteVersion++;
    _mergeApiList([selected.host]);
    await _rememberSuccessfulApiHost(selected.host);
    debugPrient("API route switched after invalid response: ${selected.host}");
    return true;
  } catch (error) {
    debugPrient(
      "API route switch failed for ${selected.host}: ${error.runtimeType}",
    );
    return false;
  }
}

String get currentApiHostName => (_apiHost);

/// API 分流地址只接受 host[:port] 形态，设置页和旧缓存可能传入完整 URL。
///
/// 前端先做一次归一化，可避免手动输入 `https://host/path` 后当前会话显示/测速
/// 仍使用完整 URL；后端保存路径会再次清洗，形成双层防护。
String normalizeApiHostCandidate(
  Object? raw, {
  String fallback = "",
}) {
  return normalizeNetworkHostCandidate(raw, fallback: fallback);
}

void _mergeApiList(Iterable<String> items) {
  _apiList = mergeNetworkHostLists(_apiList, items);
}

Future<bool> autoSelectApiHost() async {
  final hosts = _probeableApiHosts(_apiList);
  final preferred = _probeableApiHosts(
    [
      if (_lastSuccessfulApiHost.isNotEmpty) _lastSuccessfulApiHost,
      _apiHost,
    ],
    allowEmergencyFallback: false,
  );
  final fastest = await selectStartupHost(
    hosts,
    _probeApiHost,
    preferredHosts: preferred,
    fastTimeout: _automaticProbeTimeout,
  );
  if (fastest == null) return false;
  if (fastest.host.toLowerCase() != _apiHost.toLowerCase()) {
    try {
      await methods.saveApiHost(fastest.host);
    } catch (error) {
      debugPrient("autoSelectApiHost save failed: $error");
      return false;
    }
    _setCurrentApiHost(fastest.host);
  }
  await _rememberSuccessfulApiHost(fastest.host);
  return true;
}

Future<int> _probeApiHost(String host, Duration timeout) async {
  if (_apiHostHealth[host.toLowerCase()]?.blocked ?? false) {
    throw StateError('API route is temporarily blocked');
  }
  try {
    final milliseconds = await methods.ping(host, timeout: timeout);
    if (milliseconds <= 0) {
      throw StateError('API route returned an invalid probe result');
    }
    _markApiHostSuccess(host);
    return milliseconds;
  } catch (error) {
    _markApiHostFailure(host);
    rethrow;
  }
}

List<String> _probeableApiHosts(
  Iterable<String> hosts, {
  bool allowEmergencyFallback = true,
}) {
  final all = <String>[];
  final seen = <String>{};
  for (final host in hosts) {
    final normalized = host.trim();
    if (normalized.isNotEmpty && seen.add(normalized.toLowerCase())) {
      all.add(normalized);
    }
  }
  final available = all
      .where((host) => !(_apiHostHealth[host.toLowerCase()]?.blocked ?? false))
      .toList(growable: false);
  if (available.isNotEmpty) return available;
  if (all.isEmpty) return all;
  if (!allowEmergencyFallback) return const [];

  // Emergency fallback: every route is blocked. Allow one fresh probe round
  // instead of leaving the app permanently stuck with no candidates.
  for (final host in all) {
    _apiHostHealth.remove(host.toLowerCase());
  }
  unawaited(_saveApiHostHealth());
  return all;
}

Future<void> _loadApiHostHealth() async {
  try {
    final raw = await methods.loadProperty(_apiHostHealthKey);
    if (raw.trim().isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    _apiHostHealth.clear();
    decoded.forEach((key, value) {
      if (key is String && value is Map) {
        _apiHostHealth[key.toLowerCase()] = _ApiHostHealth.fromJson(
          Map<String, dynamic>.from(value),
        );
      }
    });
  } catch (_) {
    _apiHostHealth.clear();
  }
}

void _markApiHostFailure(String host) {
  final key = host.toLowerCase();
  final health = _apiHostHealth.putIfAbsent(key, () => _ApiHostHealth());
  health.failures++;
  if (health.failures >= _apiFailureThreshold) {
    health.blockedUntilMs =
        DateTime.now().add(_apiCircuitDuration).millisecondsSinceEpoch;
  }
  unawaited(_saveApiHostHealth());
}

void _markApiHostSuccess(String host) {
  final key = host.toLowerCase();
  if (_apiHostHealth.remove(key) != null) {
    unawaited(_saveApiHostHealth());
  }
}

Future<void> _saveApiHostHealth() async {
  final payload = <String, dynamic>{
    for (final entry in _apiHostHealth.entries)
      if (entry.value.failures > 0) entry.key: entry.value.toJson(),
  };
  try {
    await methods.saveProperty(_apiHostHealthKey, jsonEncode(payload));
  } catch (_) {
    // Circuit state is an optimization; probing still works if persistence fails.
  }
}

Future<void> _rememberSuccessfulApiHost(String host) async {
  if (_lastSuccessfulApiHost.toLowerCase() == host.toLowerCase()) return;
  _lastSuccessfulApiHost = host;
  try {
    await methods.saveProperty(_lastSuccessfulApiHostKey, host);
  } catch (error) {
    debugPrient(
      "saved API host persistence failed: ${error.runtimeType}",
    );
  }
}

Future<T?> chooseApiDialog<T>(BuildContext buildContext) async {
  var refreshing = false;
  return await showDialog<T>(
    context: buildContext,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder:
            (BuildContext context, void Function(void Function()) setState) {
          return SimpleDialog(
            title: Text(context.l10n.tr("API分流", en: "API routing")),
            children: [
              ..._apiList.map(
                (e) => SimpleDialogOption(
                  child: ApiOptionRow(
                    e,
                    key: Key("API:$e"),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(e);
                  },
                ),
              ),
              SimpleDialogOption(
                child: Row(
                  children: [
                    if (refreshing) ...[
                      const SizedBox(
                        key: ValueKey('api-host-refresh-progress'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      refreshing
                          ? context.l10n.tr(
                              "拉取中...",
                              en: "Refreshing...",
                            )
                          : context.l10n.tr(
                              "手动拉取",
                              en: "Refresh list",
                            ),
                    ),
                  ],
                ),
                onPressed: refreshing
                    ? null
                    : () async {
                        setState(() => refreshing = true);
                        try {
                          final latest = await methods.refreshApiHostList();
                          _mergeApiList(_fallbackApiHosts);
                          _mergeApiList(latest);
                          _mergeApiList([_apiHost]);
                          await autoSelectApiHost();
                          if (!context.mounted) {
                            return;
                          }
                          setState(() {});
                          defaultToast(
                            context,
                            context.l10n
                                .tr("分流列表已更新", en: "Routing list updated"),
                          );
                        } catch (e) {
                          debugPrient("refreshApiHostList failed: $e");
                          if (!context.mounted) {
                            return;
                          }
                          defaultToast(
                            context,
                            context.l10n.tr("拉取失败", en: "Refresh failed"),
                          );
                        } finally {
                          if (context.mounted) {
                            setState(() => refreshing = false);
                          }
                        }
                      },
              ),
              SimpleDialogOption(
                child: Text(context.l10n.tr("手动输入", en: "Manual input")),
                onPressed: () async {
                  Navigator.of(context).pop(await _manualInputApiHost(context));
                },
              ),
              SimpleDialogOption(
                child: Text(context.l10n.tr("取消", en: "Cancel")),
                onPressed: () {
                  Navigator.of(context).pop(null);
                },
              ),
            ],
          );
        },
      );
    },
  );
}

Future<String?> _manualInputApiHost(BuildContext context) {
  return displayTextInputDialog(
    context,
    title: context.l10n.tr(
      "手动输入API地址",
      en: "Enter API address manually",
    ),
    hint: "www.example.com",
    src: _apiHost,
    desc: context.l10n.tr(
      "支持域名或 host:port 格式。",
      en: "Domain or host:port format is supported.",
    ),
  );
}

class ApiOptionRow extends StatefulWidget {
  final String value;

  const ApiOptionRow(this.value, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ApiOptionRowState();
}

class _ApiOptionRowState extends State<ApiOptionRow> {
  late Future<HostPingResult> _feature;

  @override
  void initState() {
    super.initState();
    _feature = measureHostPing(() => methods.ping(widget.value));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(widget.value),
        Expanded(child: Container()),
        FutureBuilder(
          future: _feature,
          builder: (
            BuildContext context,
            AsyncSnapshot<HostPingResult> snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const NetworkPingStatus.loading();
            }
            if (snapshot.hasError) {
              return const NetworkPingStatus.failed();
            }
            return NetworkPingStatus.result(snapshot.requireData);
          },
        ),
      ],
    );
  }
}

Future chooseApiHost(BuildContext context) async {
  final choose = await chooseApiDialog(context);
  if (choose != null) {
    _apiHost = normalizeApiHostCandidate(choose, fallback: _defaultApiHost);
    await methods.saveApiHost(_apiHost);
    Methods.apiRouteVersion++;
    _mergeApiList([_apiHost]);
  }
}

void _setCurrentApiHost(String host) {
  _apiHost = host;
  Methods.apiRouteVersion++;
  _mergeApiList([_apiHost]);
}

Widget apiHostSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        leading: const Icon(Icons.dns_rounded),
        onTap: () async {
          await chooseApiHost(context);
          setState(() {});
        },
        title: Text(context.l10n.tr("API分流", en: "API routing")),
        subtitle: Text(
          context.l10n.tr(
            '自动选择：${_apiHost.isEmpty ? _defaultApiHost : _apiHost}',
            en: 'Automatic: ${_apiHost.isEmpty ? _defaultApiHost : _apiHost}',
          ),
        ),
      );
    },
  );
}
