import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('update verification sends integrity metadata to native bridge',
      () async {
    const channel = MethodChannel('methods');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'verifyUpdateApk') {
        return <String, Object>{
          'verified': true,
          'path': '/cache/update.apk',
        };
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final result = await methods.verifyUpdateApk(
      '/cache/update.apk',
      expectedSha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      expectedSize: 123456,
      expectedVersionName: 'v1.8.144',
    );

    expect(result['verified'], isTrue);
    expect(calls.single.arguments, {
      'path': '/cache/update.apk',
      'sha256':
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      'size': 123456,
      'version_name': 'v1.8.144',
    });
  });
}
