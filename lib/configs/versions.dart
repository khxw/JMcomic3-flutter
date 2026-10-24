import 'dart:async' show Future;
import 'dart:convert';

import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/http_client.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/app_icon.dart';

import 'int_property.dart';
import 'ignore_upgrade_pop.dart';

const _repoOwner = "khxw";
const _repoName = "JMcomic3-flutter";

/// Enables user-facing update checks and download entries for this fork.
const updatesTemporarilyDisabled = false;

const _releaseLatestUrl =
    "https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest";
const _releaseLatestMirrorUrls = [
  "https://ghproxy.com/https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest",
  "https://ghproxy.net/https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest",
];
const _releaseLatestPageUrl =
    "https://github.com/$_repoOwner/$_repoName/releases/latest";
const _releaseLatestPageMirrorUrls = [
  "https://r.jina.ai/http://github.com/$_repoOwner/$_repoName/releases/latest",
];
const releasePageUrl = "https://github.com/$_repoOwner/$_repoName/releases/";
const _defaultDownloadUrl = releasePageUrl;

const _versionAssets = 'lib/assets/version.txt';
final RegExp _versionExp = RegExp(r"^v\d+\.\d+\.\d+(\+\d+)?$");

late String _version;
String? _latestVersion;
String? _latestVersionName;
String? _latestVersionInfo;
String _downloadUrl = _defaultDownloadUrl;

const _propertyName = "checkVersionPeriod";
const _latestNameCacheKey = "latestVersionNameCache";
const _latestInfoCacheKey = "latestVersionInfoCache";
const _latestRepoCacheKey = "latestVersionRepoCache";
const _repoToken = "$_repoOwner/$_repoName";
final _repoTokenLower =
    "${_repoOwner.toLowerCase()}/${_repoName.toLowerCase()}";
const _useBackendAppConfig = false;
late int _period = -1;

Future initVersion() async {
  try {
    _version = (await rootBundle.loadString(_versionAssets)).trim();
  } catch (e) {
    _version = "dirty";
  }
  if (updatesTemporarilyDisabled) {
    _latestVersion = null;
    _latestVersionName = null;
    _latestVersionInfo = null;
    _downloadUrl = _defaultDownloadUrl;
    return;
  }
  _latestVersionName = await methods.loadProperty(_latestNameCacheKey);
  if (_latestVersionName == "") {
    _latestVersionName = null;
  }
  _latestVersionInfo = await methods.loadProperty(_latestInfoCacheKey);
  if (_latestVersionInfo == "") {
    _latestVersionInfo = null;
  }
  final latestRepoCache = await methods.loadProperty(_latestRepoCacheKey);
  if (latestRepoCache != _repoToken) {
    // Repo source changed: drop stale cached latest-version content.
    _latestVersionName = null;
    _latestVersionInfo = null;
    await methods.saveProperty(_latestNameCacheKey, "");
    await methods.saveProperty(_latestInfoCacheKey, "");
    await methods.saveProperty(_latestRepoCacheKey, _repoToken);
  }
  if (_latestVersionName == null && _versionExp.hasMatch(_version)) {
    _latestVersionName = _version;
  }
  final vStr = await methods.loadProperty(_propertyName);
  // 升级检查周期属于启动路径配置；旧缓存损坏时回退 0，避免版本页初始化直接抛异常。
  _period = parseBoundedIntPropertyValue(vStr, fallback: 0, min: 0);
  if (_period > 0) {
    if (DateTime.now().millisecondsSinceEpoch > _period) {
      await methods.saveProperty(_propertyName, "0");
      _period = 0;
    }
  }
}

var versionEvent = Event<EventArgs>();

String currentVersion() {
  return _version;
}

String? get latestVersion => _latestVersion;

String? get latestVersionName => _latestVersionName;

String? latestVersionInfo() {
  return _latestVersionInfo;
}

String latestDownloadUrl() {
  return _sanitizeDownloadUrl(_downloadUrl);
}

Future autoCheckNewVersion() {
  if (updatesTemporarilyDisabled) {
    return Future.value();
  }
  if (_period != 0) {
    return Future.value();
  }
  return _versionCheck();
}

Future manualCheckNewVersion(BuildContext context) async {
  if (updatesTemporarilyDisabled) {
    defaultToast(
      context,
      context.l10n.tr(
        '更新功能暂时关闭',
        en: 'Update checks are temporarily unavailable',
      ),
    );
    return;
  }
  try {
    defaultToast(context, "\u68c0\u67e5\u66f4\u65b0\u4e2d");
    await _versionCheck();
    defaultToast(context, "\u68c0\u67e5\u66f4\u65b0\u6210\u529f");
  } catch (e) {
    defaultToast(context, "\u68c0\u67e5\u66f4\u65b0\u5931\u8d25: $e");
  }
}

Future silentCheckNewVersion() async {
  if (updatesTemporarilyDisabled) return;
  await _versionCheck();
}

bool dirtyVersion() {
  return !_versionExp.hasMatch(_version);
}

Future _versionCheck() async {
  if (_versionExp.hasMatch(_version)) {
    _downloadUrl = _defaultDownloadUrl;
    var loadedByAppConfig = false;
    if (_useBackendAppConfig) {
      try {
        loadedByAppConfig = await _applyRemoteAppConfig();
      } catch (_) {
        // fall through to github release API
      }
    }
    if (!loadedByAppConfig) {
      try {
        final json = await _fetchLatestReleaseJson();
        final latestTag = json["tag_name"]?.toString().trim() ?? "";
        final latestName = json["name"]?.toString().trim() ?? "";
        final latestVersion = _pickLatestVersion(latestTag, latestName);
        if (latestVersion.isNotEmpty) {
          final body = json["body"]?.toString() ?? "";
          _latestVersionName = latestVersion;
          _latestVersionInfo = body;
          _latestVersion =
              _isVersionNewer(latestVersion, _version) ? latestVersion : null;
          await methods.saveProperty(_latestNameCacheKey, latestVersion);
          await methods.saveProperty(_latestInfoCacheKey, body);
        } else {
          _latestVersion = null;
          _latestVersionName = null;
          _latestVersionInfo = null;
        }
      } catch (e) {
        // keep cached values when network fetch fails
      }
      if ((_latestVersionInfo ?? "").trim().isEmpty) {
        final pageInfo = await _fetchLatestReleaseInfoFromPage();
        if (pageInfo != null && pageInfo.trim().isNotEmpty) {
          _latestVersionInfo = pageInfo;
          await methods.saveProperty(_latestInfoCacheKey, pageInfo);
        }
      }
    }
  }
  versionEvent.broadcast();
  debugPrient("$_latestVersion");
}

Future<bool> _applyRemoteAppConfig() async {
  final config = await methods.appConfig();
  if (config.isEmpty) {
    return false;
  }
  final remoteDownloadUrl = config["downloadUrl"]?.toString();
  final remoteDownloadUrlTrimmed = remoteDownloadUrl?.trim() ?? "";
  final safeDownloadUrl = _sanitizeDownloadUrl(remoteDownloadUrlTrimmed);
  if (remoteDownloadUrlTrimmed.isNotEmpty &&
      safeDownloadUrl == _defaultDownloadUrl &&
      remoteDownloadUrlTrimmed != _defaultDownloadUrl) {
    // Ignore remote config if it points to a non-owned repository.
    _downloadUrl = _defaultDownloadUrl;
    debugPrient(
        "ignore untrusted remote downloadUrl: $remoteDownloadUrlTrimmed");
    return false;
  }
  _downloadUrl = safeDownloadUrl;

  final latestTag = config["latestVersion"]?.toString().trim() ?? "";
  final latestName = config["latestVersionName"]?.toString().trim() ?? "";
  final latestVersion = _pickLatestVersion(latestTag, latestName);
  if (latestVersion.isEmpty) {
    return false;
  }

  final body = config["changeLog"]?.toString() ?? "";
  _latestVersionName = latestVersion;
  _latestVersionInfo = body;
  _latestVersion =
      _isVersionNewer(latestVersion, _version) ? latestVersion : null;
  await methods.saveProperty(_latestNameCacheKey, latestVersion);
  await methods.saveProperty(_latestInfoCacheKey, body);
  return true;
}

String _sanitizeDownloadUrl(String? candidate) {
  final text = (candidate ?? "").trim();
  if (text.isEmpty) {
    return _defaultDownloadUrl;
  }
  Uri uri;
  try {
    uri = Uri.parse(text);
  } catch (_) {
    return _defaultDownloadUrl;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != "http" && scheme != "https") {
    return _defaultDownloadUrl;
  }
  final lower = text.toLowerCase();
  if (!lower.contains(_repoTokenLower)) {
    return _defaultDownloadUrl;
  }
  return text;
}

String _pickLatestVersion(String tagName, String releaseName) {
  if (_versionExp.hasMatch(tagName)) {
    return tagName;
  }
  if (_versionExp.hasMatch(releaseName)) {
    return releaseName;
  }
  if (tagName.isNotEmpty) {
    return tagName;
  }
  return releaseName;
}

bool _isVersionNewer(String candidate, String current) {
  final candidateParts = _parseVersion(candidate);
  final currentParts = _parseVersion(current);
  if (candidateParts == null || currentParts == null) {
    return false;
  }
  for (var index = 0; index < 3; index++) {
    final comparison = candidateParts[index].compareTo(currentParts[index]);
    if (comparison != 0) {
      return comparison > 0;
    }
  }
  return candidateParts[3] > currentParts[3];
}

List<int>? _parseVersion(String raw) {
  final match =
      RegExp(r'^v(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$').firstMatch(raw.trim());
  if (match == null) return null;
  return [
    int.tryParse(match.group(1)!) ?? -1,
    int.tryParse(match.group(2)!) ?? -1,
    int.tryParse(match.group(3)!) ?? -1,
    int.tryParse(match.group(4) ?? '0') ?? -1,
  ];
}

@visibleForTesting
bool isVersionNewerForTest(String candidate, String current) {
  return _isVersionNewer(candidate, current);
}

Future<Map<String, dynamic>> _fetchLatestReleaseJson() async {
  final urls = [_releaseLatestUrl, ..._releaseLatestMirrorUrls];
  Object? lastError;
  for (final url in urls) {
    try {
      try {
        final text = await methods.httpGet(url);
        final decoded = jsonDecode(text);
        if (decoded is Map && _isRateLimitError(decoded)) {
          throw StateError("rate_limit");
        }
        return decoded;
      } catch (_) {
        final text = await _httpGetViaDart(url);
        final decoded = jsonDecode(text);
        if (decoded is Map && _isRateLimitError(decoded)) {
          throw StateError("rate_limit");
        }
        return decoded;
      }
    } catch (e) {
      lastError = e;
    }
  }
  if (lastError != null) {
    // ignore: only_throw_errors
    throw lastError;
  }
  return <String, dynamic>{};
}

Future<String> _httpGetViaDart(String url) async {
  return AppHttpClient.getText(
    url,
    headers: const {
      "User-Agent": "Mozilla/5.0",
      "Accept": "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
    requestTimeout: const Duration(seconds: 12),
    retries: 1,
  );
}

Future<String?> _fetchLatestReleaseInfoFromPage() async {
  final urls = [_releaseLatestPageUrl, ..._releaseLatestPageMirrorUrls];
  for (final url in urls) {
    try {
      final text = await _httpGetViaDart(url);
      final parsed = _extractReleaseBodyFromPage(text);
      if (parsed != null && parsed.trim().isNotEmpty) {
        return parsed.trim();
      }
    } catch (_) {}
  }
  return null;
}

String? _extractReleaseBodyFromPage(String text) {
  var body = text;
  final repoToken = "$_repoOwner/$_repoName";
  final hasRepoHint =
      body.contains(repoToken) || body.contains("$_repoName/releases");
  if (!hasRepoHint) {
    return null;
  }
  final marker = "Markdown Content:";
  final markerIndex = body.indexOf(marker);
  if (markerIndex >= 0) {
    body = body.substring(markerIndex + marker.length);
  } else if (body.contains("<meta") || body.contains("<html")) {
    final ogUrl = RegExp(r'property="og:url" content="([^"]*)"', dotAll: true)
            .firstMatch(body)
            ?.group(1) ??
        "";
    final ogDesc =
        RegExp(r'property="og:description" content="([^"]*)"', dotAll: true)
                .firstMatch(body)
                ?.group(1) ??
            "";
    final ogLooksLikeRelease = ogUrl.contains(repoToken) &&
        (ogUrl.contains("/releases/tag/") ||
            ogUrl.contains("/releases/latest"));
    if (ogLooksLikeRelease && ogDesc.trim().isNotEmpty) {
      final desc = _decodeHtmlEntities(ogDesc);
      if (desc.trim().isNotEmpty) {
        return desc.trim();
      }
    }
    final md = RegExp(
      r'<div[^>]*class="[^"]*markdown-body[^"]*"[^>]*>([\s\S]*?)</div>',
      caseSensitive: false,
    ).firstMatch(body);
    if (md != null) {
      body = md.group(1) ?? "";
      body = body
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), "\n")
          .replaceAll(RegExp(r'</p>', caseSensitive: false), "\n")
          .replaceAll(RegExp(r'</li>', caseSensitive: false), "\n");
      body = body.replaceAll(RegExp(r'<[^>]+>'), "");
      body = _decodeHtmlEntities(body).trim();
    }
  }
  body = body.trim();
  if (body.isEmpty) return null;
  final assetsIndex = body.indexOf("## Assets");
  if (assetsIndex > 0) {
    body = body.substring(0, assetsIndex).trim();
  }
  final lines = body.split("\n");
  if (lines.isNotEmpty && lines.first.startsWith("#")) {
    body = lines.skip(1).join("\n").trim();
  }
  return body.isEmpty ? null : body;
}

bool _isRateLimitError(Map<dynamic, dynamic> json) {
  final message = json["message"];
  if (message is! String) return false;
  return message.toLowerCase().contains("rate limit");
}

String _decodeHtmlEntities(String input) {
  return input
      .replaceAll("&amp;", "&")
      .replaceAll("&lt;", "<")
      .replaceAll("&gt;", ">")
      .replaceAll("&quot;", "\"")
      .replaceAll("&#39;", "'");
}

String _periodText() {
  if (_period < 0) {
    return "\u81ea\u52a8\u68c0\u67e5\u66f4\u65b0\u5df2\u5173\u95ed";
  }
  if (_period == 0) {
    return "\u81ea\u52a8\u68c0\u67e5\u66f4\u65b0\u5df2\u5f00\u542f";
  }
  return "\u4e0b\u6b21\u68c0\u67e5\u65f6\u95f4: " +
      formatDateTimeToDateTime(
        DateTime.fromMillisecondsSinceEpoch(_period),
      );
}

Future _choosePeriod(BuildContext context) async {
  var result = await chooseListDialog(
    context,
    title: "\u81ea\u52a8\u68c0\u67e5\u66f4\u65b0",
    values: [
      "\u5f00\u542f",
      "\u4e00\u5468\u540e",
      "\u4e00\u4e2a\u6708\u540e",
      "\u4e00\u5e74\u540e",
      "\u5173\u95ed"
    ],
    tips: "\u91cd\u542f\u540e\u7ea2\u70b9\u4f1a\u6d88\u5931",
  );
  switch (result) {
    case "\u5f00\u542f":
      await methods.saveProperty(_propertyName, "0");
      _period = 0;
      break;
    case "\u4e00\u5468\u540e":
      var time = DateTime.now().millisecondsSinceEpoch + (1000 * 3600 * 24 * 7);
      await methods.saveProperty(_propertyName, "$time");
      _period = time;
      break;
    case "\u4e00\u4e2a\u6708\u540e":
      var time =
          DateTime.now().millisecondsSinceEpoch + (1000 * 3600 * 24 * 30);
      await methods.saveProperty(_propertyName, "$time");
      _period = time;
      break;
    case "\u4e00\u5e74\u540e":
      var time =
          DateTime.now().millisecondsSinceEpoch + (1000 * 3600 * 24 * 365);
      await methods.saveProperty(_propertyName, "$time");
      _period = time;
      break;
    case "\u5173\u95ed":
      await methods.saveProperty(_propertyName, "-1");
      _period = -1;
      break;
  }
}

Widget autoUpdateCheckSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: const Text("\u81ea\u52a8\u68c0\u67e5\u66f4\u65b0"),
        subtitle: Text(_periodText()),
        onTap: () async {
          await _choosePeriod(context);
          setState(() {});
        },
      );
    },
  );
}

String formatDateTimeToDateTime(DateTime c) {
  try {
    return "${add0(c.year, 4)}-${add0(c.month, 2)}-${add0(c.day, 2)} ${add0(c.hour, 2)}:${add0(c.minute, 2)}";
  } catch (e) {
    return "-";
  }
}

var _display = true;

void versionPop(BuildContext context) {
  if (updatesTemporarilyDisabled) return;
  if (latestVersion != null && _display && !currentIgnoreUpgradePop()) {
    _display = false;
    _showUpdatePrompt(context);
  }
}

void _showUpdatePrompt(BuildContext context) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: .5),
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) {
      return _UpdatePromptDialog(
        current: currentVersion(),
        latest: latestVersion ?? latestVersionName ?? currentVersion(),
        summary: _updatePromptSummary(
          latestVersionInfo(),
          context.l10n.tr(
            '包含界面优化、功能改进和问题修复。',
            en: 'Includes UI, feature, and reliability improvements.',
          ),
        ),
        onLater: () => Navigator.of(dialogContext).pop(),
        onOpenRelease: () {
          Navigator.of(dialogContext).pop();
          openUrl(latestDownloadUrl());
        },
      );
    },
    transitionBuilder: (_, animation, secondaryAnimation, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _UpdatePromptDialog extends StatelessWidget {
  final String current;
  final String latest;
  final String summary;
  final VoidCallback onLater;
  final VoidCallback onOpenRelease;

  const _UpdatePromptDialog({
    required this.current,
    required this.latest,
    required this.summary,
    required this.onLater,
    required this.onOpenRelease,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Dialog(
        key: const ValueKey('update-prompt-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .4),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 14, 17),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primaryContainer,
                      scheme.tertiaryContainer.withValues(alpha: .72),
                    ],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      key: const ValueKey('update-prompt-app-icon'),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const AppIcon(
                        size: 46,
                        borderRadius: 13,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.tr(
                              '发现新版本',
                              en: 'Update available',
                            ),
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.l10n.tr(
                              '新版本已准备好，可以前往发布页面下载。',
                              en: 'A new version is ready on the release page.',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onPrimaryContainer
                                  .withValues(alpha: .7),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.tr('稍后', en: 'Later'),
                      onPressed: onLater,
                      icon: Icon(
                        Icons.close_rounded,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final scale =
                              MediaQuery.textScalerOf(context).scale(14) / 14;
                          final stack =
                              constraints.maxWidth < 300 || scale > 1.35;
                          final currentTile = _PromptVersionTile(
                            label: context.l10n.currentVersion,
                            version: current,
                          );
                          final latestTile = _PromptVersionTile(
                            label: context.l10n.latestVersion,
                            version: latest,
                            highlighted: true,
                          );
                          if (stack) {
                            return Column(
                              children: [
                                currentTile,
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 5),
                                  child: Icon(
                                    Icons.south_rounded,
                                    size: 18,
                                  ),
                                ),
                                latestTile,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: currentTile),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 9),
                                child: Icon(Icons.east_rounded, size: 18),
                              ),
                              Expanded(child: latestTile),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 13),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: .38),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.notes_rounded,
                                  size: 17,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  context.l10n.updateContent,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Text(
                              summary,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final stack = constraints.maxWidth < 300 || scale > 1.3;
                    final later = OutlinedButton(
                      key: const ValueKey('update-prompt-later'),
                      onPressed: onLater,
                      child: Text(context.l10n.tr('稍后', en: 'Later')),
                    );
                    final update = FilledButton.icon(
                      key: const ValueKey('update-prompt-open'),
                      onPressed: onOpenRelease,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(
                        context.l10n.tr('前往更新', en: 'Open update'),
                      ),
                    );
                    if (stack) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          update,
                          const SizedBox(height: 8),
                          later,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: later),
                        const SizedBox(width: 9),
                        Expanded(child: update),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptVersionTile extends StatelessWidget {
  final String label;
  final String version;
  final bool highlighted;

  const _PromptVersionTile({
    required this.label,
    required this.version,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primaryContainer.withValues(alpha: .58)
            : scheme.surfaceContainerHighest.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            version,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: highlighted ? scheme.onPrimaryContainer : null,
            ),
          ),
        ],
      ),
    );
  }
}

String _updatePromptSummary(String? raw, String fallback) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) {
    return fallback;
  }
  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .where((line) => !line.startsWith('#'))
      .map(
        (line) => line
            .replaceAll(RegExp(r'^[-*]\s*'), '')
            .replaceAll(RegExp(r'[*_`>]'), ''),
      )
      .where((line) => line.isNotEmpty)
      .take(3)
      .join('\n');
  return lines.isEmpty ? fallback : lines;
}
