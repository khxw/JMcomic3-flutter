import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_pager.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';
import 'package:jmcomic3/screens/week_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('weekly refresh and issue switch send current API parameters',
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

    await initPagerControllerMode();
    await initPagerViewMode();
    await initPagerCoverRate();
    await initPagerColumnCount();
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
              {'id': 'hot', 'title': 'Hot'},
            ],
          }),
          initialCategoryId: 'issue-1',
          categoryNotifier: categoryNotifier,
          onCategoryChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final issueSelector = find.byKey(const ValueKey('week-issue-selector'));
    final typeSelector = find.byKey(const ValueKey('week-type-selector'));
    expect(issueSelector, findsOneWidget);
    expect(typeSelector, findsOneWidget);
    expect(find.byKey(const ValueKey('week-issue-header')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('week-type-hot')),
        matching: find.text('Hot'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(issueSelector).bottom,
      lessThan(tester.getRect(typeSelector).top),
    );
    expect(
      tester.getRect(typeSelector).bottom,
      lessThan(tester.getRect(find.byType(ComicPager)).top),
    );
    expect(requests, [
      {'category_id': 'issue-1', 'type_id': 'hot', 'page': 1},
    ]);

    // 调用分页器实际的刷新入口，回归“内层已刷新但每周必看仍命中旧缓存”的问题。
    final builder = tester.widget<ContentBuilder<dynamic>>(
        find.byWidgetPredicate((widget) => widget is ContentBuilder));
    await builder.onRefresh();
    await tester.pumpAndSettle();
    expect(requests, [
      {'category_id': 'issue-1', 'type_id': 'hot', 'page': 1},
      {'category_id': 'issue-1', 'type_id': 'hot', 'page': 1},
    ]);
    await tester.tap(
      find.byKey(const ValueKey('week-issue-choice-issue-2')),
    );
    await tester.pumpAndSettle();
    expect(categoryNotifier.value, 'issue-2');
    expect(
        requests.last, {'category_id': 'issue-2', 'type_id': 'hot', 'page': 1});
    expect(requests, hasLength(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
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

    await initPagerControllerMode();
    await initPagerViewMode();
    await initPagerCoverRate();
    await initPagerColumnCount();
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

    final issues =
        tester.getRect(find.byKey(const ValueKey('week-issue-selector')));
    final selector =
        tester.getRect(find.byKey(const ValueKey('week-type-selector')));
    expect(issues.left, greaterThanOrEqualTo(0));
    expect(issues.right, lessThanOrEqualTo(320));
    expect(selector.left, greaterThanOrEqualTo(0));
    expect(selector.right, lessThanOrEqualTo(320));
    expect(
      tester.getSize(find.byKey(const ValueKey('week-type-hot'))).height,
      greaterThanOrEqualTo(40),
    );
    expect(tester.takeException(), isNull);
  });
}
