import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
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
        case 'comic_search':
          return _response({
            'total': 0,
            'content': <Object>[],
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

    await initPagerViewMode();
    await initPagerControllerMode();
    await initPagerCoverRate();
    await initPagerColumnCount();
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

  testWidgets('back from search results returns to the search landing page',
      (tester) async {
    final histories = <Map<String, Object>>[
      {
        'search_query': 'quiet forest',
        'last_search_time': 1770000000,
      },
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (request['method']) {
        case 'last_search_histories':
          return _response(histories);
        case 'categories':
          return _response({
            'categories': <Object>[],
            'blocks': <Object>[],
          });
        case 'comic_search':
          final params =
              jsonDecode(request['params'] as String) as Map<String, dynamic>;
          final query = params['search_query'] as String;
          histories.removeWhere(
            (item) => item['search_query'] == query,
          );
          histories.insert(0, {
            'search_query': query,
            'last_search_time': 1770000100,
          });
          return _response({
            'total': 0,
            'content': <Object>[],
          });
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

    await tester.enterText(
      find.byKey(const ValueKey('compose-search-field')),
      'brand new',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Search results'), findsOneWidget);
    expect(histories.first['search_query'], 'brand new');
    // The standalone search harness does not mount the full app shell.
    tester.takeException();

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('Search results'), findsNothing);
    expect(find.text('brand new'), findsOneWidget);
  });
}
