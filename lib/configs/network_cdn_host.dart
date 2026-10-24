import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/network_host.dart';
import 'package:jmcomic3/configs/network_ping.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _defaultCdnHost = "cdn-msp3.jmapiproxy1.cc";
String _cdnHost = _defaultCdnHost;

String _truncateLabel(String value, {int max = 21}) {
  if (value.length <= max) return value;
  return value.substring(0, max) + "...";
}

String get currentCdnHostName => _cdnHost;

// 优先提供参考项目当前的移动端图片域名，旧域名继续保留供用户手动测速选择。
const _builtinCdnHosts = <String>[
  "cdn-msp.jmapiproxy1.cc",
  "cdn-msp.jmapiproxy2.cc",
  "cdn-msp2.jmapiproxy2.cc",
  "cdn-msp3.jmapiproxy2.cc",
  "cdn-msp.jmapinodeudzn.net",
  "cdn-msp3.jmapinodeudzn.net",
  "cdn-msp3.jmdanjonproxy.vip",
  "cdn-msp.jmapiproxy3.net",
  "cdn-msp2.jmapinodeudzn.net",
  "cdn-msp2.jmapiproxy1.cc",
];

List<String> _cdnList = [];

Future<void> initCdnHost() async {
  _cdnList = [];
  _mergeCdnList([
    _defaultCdnHost,
    ..._builtinCdnHosts,
  ]);
  final rawLoaded = await methods.loadCdnHost();
  final loaded =
      normalizeNetworkHostCandidate(rawLoaded, fallback: _defaultCdnHost);
  _cdnHost = loaded;
  _mergeCdnList([_cdnHost]);
  if (rawLoaded.trim() != _cdnHost) {
    await methods.saveCdnHost(_cdnHost);
  }
}

Future chooseCdnHost(BuildContext context) async {
  final choose = await chooseCdnDialog(context);
  if (choose != null) {
    _cdnHost = normalizeNetworkHostCandidate(choose, fallback: _defaultCdnHost);
    await methods.saveCdnHost(_cdnHost);
    _mergeCdnList([_cdnHost]);
  }
}

void _mergeCdnList(Iterable<String> items) {
  _cdnList = mergeNetworkHostLists(_cdnList, items);
}

Widget cdnHostSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        onTap: () async {
          await chooseCdnHost(context);
          setState(() {});
        },
        title: Text(context.l10n.tr("图片分流", en: "Image routing")),
        subtitle: Text(_cdnHost.isEmpty ? _defaultCdnHost : _cdnHost),
      );
    },
  );
}

Future<T?> chooseCdnDialog<T>(BuildContext buildContext) async {
  return await showDialog<T>(
    context: buildContext,
    builder: (BuildContext context) {
      final dialogWidth = MediaQuery.of(context).size.width * 0.86;
      return SimpleDialog(
        title: Text(context.l10n.tr("图片分流", en: "Image routing")),
        children: [
          ..._cdnList.map(
            (e) => SimpleDialogOption(
              child: SizedBox(
                width: dialogWidth,
                child: CdnOptionRow(
                  e,
                  key: Key("CDN:$e"),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop(e);
              },
            ),
          ),
          SimpleDialogOption(
            child: SizedBox(
              width: dialogWidth,
              child: Text(context.l10n.tr("手动输入", en: "Manual input")),
            ),
            onPressed: () async {
              Navigator.of(context).pop(await _manualInputApiHost(context));
            },
          ),
          SimpleDialogOption(
            child: SizedBox(
              width: dialogWidth,
              child: Text(context.l10n.tr("取消", en: "Cancel")),
            ),
            onPressed: () {
              Navigator.of(context).pop(null);
            },
          ),
        ],
      );
    },
  );
}

Future<String?> _manualInputApiHost(BuildContext context) {
  return displayTextInputDialog(
    context,
    title: context.l10n.tr(
      "手动输入CDN地址",
      en: "Enter CDN address manually",
    ),
    hint: "www.example.com",
    src: _cdnHost,
    desc: context.l10n.tr(
      "支持域名或 host:port 格式。",
      en: "Domain or host:port format is supported.",
    ),
  );
}

class CdnOptionRow extends StatefulWidget {
  final String value;

  const CdnOptionRow(this.value, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CdnOptionRowState();
}

class _CdnOptionRowState extends State<CdnOptionRow> {
  late Future<HostPingResult> _feature;

  @override
  void initState() {
    super.initState();
    _feature = measureHostPing(() => methods.pingCdn(widget.value));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _truncateLabel(widget.value),
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
            ),
          ),
          const SizedBox(width: 8),
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
      ),
    );
  }
}
