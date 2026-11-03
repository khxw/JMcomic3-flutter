import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/remember_login.dart';

const _channel = MethodChannel('methods');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remembered credentials can be saved, loaded and cleared', () async {
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
      }
      return _response('');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await saveRememberedLogin('reader@example.com', 'secret', remember: true);
    final saved = await loadRememberedLogin();
    expect(saved.username, 'reader@example.com');
    expect(saved.password, 'secret');
    expect(saved.remember, isTrue);

    await clearRememberedLogin();
    final cleared = await loadRememberedLogin();
    expect(cleared.username, isEmpty);
    expect(cleared.password, isEmpty);
    expect(cleared.remember, isFalse);
  });
}

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });
