import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/search_screen.dart';

const _channel = MethodChannel('methods');

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recent searches can collapse and expand without clearing',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (request['method']) {
        case 'last_search_histories':
          return _response([
            {
              'search_query': 'quiet forest',
              'last_search_time': 1770000000,
            },
            {
              'search_query': 'city rain',
              'last_search_time': 1769990000,
            },
          ]);
        case 'categories':
          return _response({
            'categories': <Object>[],
            'blocks': <Object>[],
          });
        case 'load_property':
          return _response('');
        default:
          return _response('');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
    });

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SearchScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('search-history-toggle'));
    expect(toggle, findsOneWidget);
    expect(find.text('quiet forest'), findsOneWidget);
    expect(find.text('city rain'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('quiet forest'), findsNothing);
    expect(find.text('city rain'), findsNothing);
    expect(toggle, findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('quiet forest'), findsOneWidget);
    expect(find.text('city rain'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
