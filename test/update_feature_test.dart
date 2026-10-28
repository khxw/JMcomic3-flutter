import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/versions.dart';

const _channel = MethodChannel('methods');

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': jsonEncode(data),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only a semantically newer release is treated as an update', () {
    const current = 'v1.7.65+94';
    expect(isVersionNewerForTest('v1.7.64+93', current), isFalse);
    expect(isVersionNewerForTest('v1.7.65+93', current), isFalse);
    expect(isVersionNewerForTest('v1.7.65+94', current), isFalse);
    expect(isVersionNewerForTest('v1.7.65+95', current), isTrue);
    expect(isVersionNewerForTest('v1.7.66+0', current), isTrue);
    expect(isVersionNewerForTest('v1.8.0+0', current), isTrue);
    expect(isVersionNewerForTest('v2.0.0+0', current), isTrue);
    expect(isVersionNewerForTest('invalid', current), isFalse);
  });

  test('update checks are enabled for the fork release source', () async {
    final properties = <String, String>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final method = request['method'];
      final params = request['params']?.toString() ?? '';
      switch (method) {
        case 'load_property':
          return _response(properties[params] ?? '');
        case 'save_property':
          final values = jsonDecode(params) as Map;
          properties[values['k'] as String] = values['v'] as String;
          return _response('');
        default:
          return _response('');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    expect(updatesTemporarilyDisabled, isFalse);
    await initVersion();

    expect(RegExp(r'^v\d+\.\d+\.\d+\+\d+$').hasMatch(currentVersion()), isTrue);
    expect(latestVersion, isNull);
    expect(latestVersionName, currentVersion());
    expect(
      properties['latestVersionRepoCache'],
      'khxw/JMcomic3-flutter',
    );
    expect(
      releasePageUrl,
      'https://github.com/khxw/JMcomic3-flutter/releases/',
    );
    expect(
      projectHomeUrl,
      'https://github.com/khxw/JMcomic3-flutter',
    );
  });

  test('update check selects and caches the trusted ARM64 APK asset', () async {
    final properties = <String, String>{
      'latestVersionRepoCache': 'khxw/JMcomic3-flutter',
    };
    final digest = List.filled(64, 'b').join();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final method = request['method'];
      final params = request['params']?.toString() ?? '';
      switch (method) {
        case 'load_property':
          return _response(properties[params] ?? '');
        case 'save_property':
          final values = jsonDecode(params) as Map;
          properties[values['k'] as String] = values['v'] as String;
          return _response('');
        case 'http_get':
          return _response({
            'tag_name': 'v9.9.9',
            'name': 'JMComic3 Mod v9.9.9',
            'body': '## 更新内容\n\n- 测试版本',
            'assets': [
              {
                'name': 'JMComic3-Mod-v9.9.9-armeabi-v7a-release.apk',
                'size': 1111,
                'digest': 'sha256:${List.filled(64, 'a').join()}',
                'browser_download_url':
                    'https://github.com/khxw/JMcomic3-flutter/releases/download/v9.9.9/arm32.apk',
              },
              {
                'name': 'JMComic3-Mod-v9.9.9-arm64-v8a-release.apk',
                'size': 23325560,
                'digest': 'sha256:$digest',
                'browser_download_url':
                    'https://github.com/khxw/JMcomic3-flutter/releases/download/v9.9.9/arm64.apk',
              },
              {
                'name': 'JMComic3-Mod-v9.9.9-arm64-v8a-other.apk',
                'browser_download_url':
                    'https://example.com/khxw/JMcomic3-flutter/arm64.apk',
              },
            ],
          });
        default:
          return _response('');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await initVersion();
    await silentCheckNewVersion();

    expect(latestVersion, 'v9.9.9');
    expect(
      latestApkAssetName(),
      'JMComic3-Mod-v9.9.9-arm64-v8a-release.apk',
    );
    expect(
      latestApkDownloadUrl(),
      'https://github.com/khxw/JMcomic3-flutter/releases/download/v9.9.9/arm64.apk',
    );
    expect(latestApkSha256(), digest);
    expect(latestApkSize(), 23325560);
    expect(properties['latestApkMetadataCache'], contains('arm64-v8a'));
  });
}
