import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/configs/network_host.dart';
import 'package:jmcomic3/configs/network_ping.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _defaultApiHost = "www.cdngwc.club";
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

Future<void> initApiHost() async {
  _apiList = [];
  _mergeApiList(_fallbackApiHosts);
  try {
    _mergeApiList(await methods.loadApiHostList());
  } catch (e) {
    debugPrient("initApiHost loadApiHostList failed: $e");
    // Keep local fallback list when backend list is unavailable.
  }
  final rawLoaded = await methods.loadApiHost();
  final loaded =
      normalizeApiHostCandidate(rawLoaded, fallback: _defaultApiHost);
  _apiHost = loaded;
  _mergeApiList([_apiHost]);
  if (rawLoaded.trim() != _apiHost) {
    await methods.saveApiHost(_apiHost);
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
                    if (!context.mounted) {
                      return;
                    }
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n
                            .tr("分流列表已更新", en: "Routing list updated")),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  } catch (e) {
                    debugPrient("refreshApiHostList failed: $e");
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text(context.l10n.tr("拉取失败", en: "Refresh failed")),
                        duration: const Duration(seconds: 2),
                      ),
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
    _mergeApiList([_apiHost]);
  }
}

Widget apiHostSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        onTap: () async {
          await chooseApiHost(context);
          setState(() {});
        },
        title: Text(context.l10n.tr("API分流", en: "API routing")),
        subtitle: Text(_apiHost.isEmpty ? _defaultApiHost : _apiHost),
      );
    },
  );
}
