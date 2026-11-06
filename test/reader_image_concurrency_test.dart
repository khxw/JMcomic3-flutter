import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reader page requests are limited to four concurrent bridge calls',
      () async {
    var active = 0;
    var maximumActive = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('methods'),
      (call) async {
        final request =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
        if (request['method'] != 'jm_page_image') return null;
        active++;
        if (active > maximumActive) maximumActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return jsonEncode({
          'error_message': '',
          'response_data': '/tmp/page.webp',
        });
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('methods'),
        null,
      ),
    );

    await Future.wait(
      List.generate(
        12,
        (index) => methods.jmPageImage(index + 1, '$index.webp'),
      ),
    );

    expect(maximumActive, 4);
    expect(active, 0);
  });
}
