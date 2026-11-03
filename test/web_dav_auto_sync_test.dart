import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/web_dav_sync.dart';
import 'package:jmcomic3/configs/web_dav_password.dart';
import 'package:jmcomic3/configs/web_dav_sync_switch.dart';
import 'package:jmcomic3/configs/web_dav_url.dart';
import 'package:jmcomic3/configs/web_dav_username.dart';

const _channel = MethodChannel('methods');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('auto sync skips WebDAV without a configured account',
      (tester) async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final method = request['method'] as String;
      final params = request['params']?.toString() ?? '';
      calls.add(method);
      if (method == 'load_property' && params == 'webDavSyncSwitch') {
        return _response('true');
      }
      return _response('');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await initWebDavSyncSwitch();
    await initWebDavUrl();
    await initWebDavUserName();
    await initWebDavPassword();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => webDavSyncAuto(context),
          child: const Text('Sync'),
        ),
      ),
    ));
    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();

    expect(calls, isNot(contains('web_dav_sync')));
    expect(tester.takeException(), isNull);
  });
}

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });
