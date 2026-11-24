import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/configs/network_host.dart';
import 'package:jmcomic3/configs/network_ping.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _defaultApiHost = "www.cdngwc.club";
const _automaticProbeTimeout = Duration(milliseconds: 800);
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

List<String> _apiList = [];
Future<bool>? _apiRotationInflight;

Future<void> initApiHost() async {
  Methods.apiHostRecoveryHandler = rotateApiHostAfterInvalidResponse;
  _apiList = [];
  _mergeApiList(_fallbackApiHosts);
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
  final current = _apiHost.toLowerCase();
  final currentIndex =
      _apiList.indexWhere((host) => host.toLowerCase() == current);
  final start = currentIndex >= 0 ? currentIndex + 1 : 0;
  for (var offset = 0; offset < _apiList.length; offset++) {
    final candidate = _apiList[(start + offset) % _apiList.length];
    if (candidate.toLowerCase() == current) continue;
    try {
      await methods.saveApiHost(candidate);
      _apiHost = candidate;
      Methods.apiRouteVersion++;
      _mergeApiList([candidate]);
      debugPrient("API route switched after invalid response: $candidate");
      return true;
    } catch (error) {
      debugPrient(
        "API route switch failed for $candidate: ${error.runtimeType}",
      );
    }
  }
  return false;
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
  final fastest = await selectFastestHost(
    _apiList,
    (host, timeout) => methods.ping(host, timeout: timeout),
    timeout: _automaticProbeTimeout,
    returnOnFirstSuccess: false,
  );
  if (fastest == null) return false;
  if (fastest.host.toLowerCase() == _apiHost.toLowerCase()) {
    return true;
  }
  try {
    await methods.saveApiHost(fastest.host);
  } catch (error) {
    debugPrient("autoSelectApiHost save failed: $error");
    return false;
  }
  _setCurrentApiHost(fastest.host);
  return true;
}

Future<T?> chooseApiDialog<T>(BuildContext buildContext) async {
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
                child: Text(context.l10n.tr("手动拉取", en: "Refresh list")),
                onPressed: () async {
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
                      context.l10n.tr("分流列表已更新", en: "Routing list updated"),
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
