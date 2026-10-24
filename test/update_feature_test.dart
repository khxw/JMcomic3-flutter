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
    const current = 'v1.7.47+76';
    expect(isVersionNewerForTest('v1.7.46+75', current), isFalse);
    expect(isVersionNewerForTest('v1.7.47+75', current), isFalse);
    expect(isVersionNewerForTest('v1.7.47+76', current), isFalse);
    expect(isVersionNewerForTest('v1.7.47+77', current), isTrue);
    expect(isVersionNewerForTest('v1.7.48+0', current), isTrue);
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
  });
}
