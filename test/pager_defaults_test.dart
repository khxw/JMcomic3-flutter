import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';

const _channel = MethodChannel('methods');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first launch defaults to title-and-cover 2 with three columns',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      if (request['method'] != 'load_property') {
        return jsonEncode({
          'error_message': '',
          'response_data': '',
        });
      }
      return jsonEncode({
        'error_message': '',
        'response_data': '',
      });
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await initPagerViewMode();
    await initPagerColumnCount();

    expect(currentPagerViewMode, PagerViewMode.titleAndCover);
    expect(pagerColumnNumber, 3);
  });
}
