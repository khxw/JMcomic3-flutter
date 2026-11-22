import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_error.dart';

void main() {
  testWidgets('content error hides login text and refreshes with feedback',
      (tester) async {
    final refreshGate = Completer<void>();
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ContentError(
            error: 'JM API error 0: 请先登录',
            stackTrace: StackTrace.current,
            onRefresh: () {
              refreshCount++;
              return refreshGate.future;
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('请先登录'), findsNothing);
    expect(find.text('内容加载失败'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('content-error-refresh')));
    await tester.pump();

    expect(refreshCount, 1);
    expect(find.text('正在刷新'), findsOneWidget);

    refreshGate.complete();
    await tester.pumpAndSettle();

    expect(find.text('重新加载'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
