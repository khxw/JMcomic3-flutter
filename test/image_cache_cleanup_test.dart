import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/image_cache_cleanup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('image cache cleanup sends only selected dates', (tester) async {
    final clearedDates = <List<dynamic>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('methods'),
      (call) async {
        final request = jsonDecode(call.arguments as String) as Map;
        final method = request['method'];
        final params = jsonDecode(request['params'] as String) as Map;
        Object response;
        if (method == 'image_cache_days') {
          response = {
            'days': [
              {'date': '2026-11-08', 'files': 2, 'bytes': 2048},
              {'date': '2026-11-07', 'files': 3, 'bytes': 3072},
            ],
          };
        } else if (method == 'clear_image_cache_days') {
          clearedDates.add(List<dynamic>.from(params['dates'] as List));
          response = {'deleted_files': 2, 'deleted_bytes': 2048};
        } else {
          response = '';
        }
        return jsonEncode({
          'error_message': '',
          'response_data': jsonEncode(response),
        });
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('methods'),
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ImageCacheCleanupScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026-11-08'), findsOneWidget);
    expect(find.text('2026-11-07'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('image-cache-day-2026-11-08')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('image-cache-clear-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(clearedDates, [
      ['2026-11-08'],
    ]);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
