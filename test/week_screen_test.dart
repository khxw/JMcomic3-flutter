import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/week_comic_feed.dart';
import 'package:jmcomic3/screens/week_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('weekly type filter separates Korean and Japanese comics', () {
    ComicSimple comic(String category) => ComicSimple(
          id: 1,
          author: '',
          description: '',
          name: 'Comic',
          image: '',
          category: ComicSimpleCategory(title: category),
          categorySub: ComicSimpleCategory(title: category),
        );

    final korean = comic('韩漫');
    final japanese = comic('日漫');
    final other = comic('同人');
    expect(weekComicMatchesType(korean, 'hanman'), isTrue);
    expect(weekComicMatchesType(japanese, 'hanman'), isFalse);
    expect(weekComicMatchesType(japanese, 'japanese'), isTrue);
    expect(weekComicMatchesType(korean, 'japanese'), isFalse);
    expect(weekComicMatchesType(other, 'other'), isTrue);
    expect(weekComicMatchesType(korean, 'other'), isFalse);
  });

  testWidgets('weekly type and category changes send current API parameters',
      (tester) async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final requests = <Map<String, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final payload = jsonDecode(call.arguments as String);
      if (payload['method'] == 'load_property') {
        return jsonEncode({
          'error_message': '',
          'response_data': payload['params'] == 'pager_controller_mode'
              ? 'PagerControllerMode.pager'
              : '',
        });
      }
      if (payload['method'] == 'week_filter') {
        requests.add(
            Map<String, dynamic>.from(jsonDecode(payload['params'] as String)));
        return jsonEncode({
          'error_message': '',
          'response_data': jsonEncode({'list': <Object>[], 'total': 0}),
        });
      }
      throw StateError('Unexpected method: ${payload['method']}');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final categoryNotifier = ValueNotifier<String?>('issue-1');
    addTearDown(categoryNotifier.dispose);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        body: WeekContent(
          data: WeekData.fromJson({
            'categories': [
              {'id': 'issue-1', 'time': '2026-10-07', 'title': 'Issue 1'},
              {'id': 'issue-2', 'time': '2026-09-30', 'title': 'Issue 2'},
            ],
            'type': [
              {'id': 'hanman', 'title': ''},
            ],
          }),
          initialCategoryId: 'issue-1',
          categoryNotifier: categoryNotifier,
          onCategoryChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final typeSelector = find.byKey(const ValueKey('week-type-selector'));
    expect(typeSelector, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('week-type-hanman')),
        matching: find.text('Korean comics'),
      ),
      findsOneWidget,
    );
    expect(requests, [
      {'category_id': 'issue-1', 'type_id': 'hanman', 'page': 1},
    ]);

    categoryNotifier.value = 'issue-2';
    await tester.pumpAndSettle();
    expect(categoryNotifier.value, 'issue-2');
    expect(requests.last,
        {'category_id': 'issue-2', 'type_id': 'hanman', 'page': 1});
    expect(requests, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('weekly issue menu switches the active category', (tester) async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final requests = <Map<String, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final payload = jsonDecode(call.arguments as String);
      if (payload['method'] == 'load_property') {
        return jsonEncode({'error_message': '', 'response_data': ''});
      }
      if (payload['method'] == 'week') {
        return jsonEncode({
          'error_message': '',
          'response_data': jsonEncode({
            'categories': [
              {'id': 'issue-1', 'time': '2026-10-07', 'title': 'Issue 1'},
              {'id': 'issue-2', 'time': '2026-09-30', 'title': 'Issue 2'},
            ],
            'type': [
              {'id': 'hot', 'title': 'Hot'},
            ],
          }),
        });
      }
      if (payload['method'] == 'week_filter') {
        requests.add(
          Map<String, dynamic>.from(jsonDecode(payload['params'] as String)),
        );
        return jsonEncode({
          'error_message': '',
          'response_data': jsonEncode({'list': <Object>[], 'total': 0}),
        });
      }
      throw StateError('Unexpected method: ${payload['method']}');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: [AppLocalizations.delegate],
      home: WeekScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('week-issue-menu')), findsOneWidget);
    expect(requests.single['category_id'], 'issue-1');

    await tester.tap(find.byKey(const ValueKey('week-issue-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-09-30').last);
    await tester.pumpAndSettle();

    expect(requests.last['category_id'], 'issue-2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly layout stays compact with large text', (tester) async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final payload = jsonDecode(call.arguments as String);
      if (payload['method'] == 'load_property') {
        return jsonEncode({
          'error_message': '',
          'response_data': payload['params'] == 'pager_controller_mode'
              ? 'PagerControllerMode.pager'
              : '',
        });
      }
      if (payload['method'] == 'week_filter') {
        return jsonEncode({
          'error_message': '',
          'response_data': jsonEncode({'list': <Object>[], 'total': 0}),
        });
      }
      throw StateError('Unexpected method: ${payload['method']}');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final categoryNotifier = ValueNotifier<String?>('issue-1');
    addTearDown(categoryNotifier.dispose);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: WeekContent(
          data: WeekData.fromJson({
            'categories': [
              {
                'id': 'issue-1',
                'time': '2026-10-07',
                'title': '本周精选特别企划',
              },
              {
                'id': 'issue-2',
                'time': '2026-09-30',
                'title': 'Issue 2',
              },
            ],
            'type': [
              {'id': 'hot', 'title': 'Hot'},
              {'id': 'new', 'title': 'New'},
            ],
          }),
          initialCategoryId: 'issue-1',
          categoryNotifier: categoryNotifier,
          onCategoryChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final selector =
        tester.getRect(find.byKey(const ValueKey('week-type-selector')));
    expect(selector.left, greaterThanOrEqualTo(0));
    expect(selector.right, lessThanOrEqualTo(320));
    expect(
      tester.getSize(find.byKey(const ValueKey('week-type-hot'))).height,
      greaterThanOrEqualTo(40),
    );
    expect(tester.takeException(), isNull);
  });
}
