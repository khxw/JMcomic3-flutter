import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/app_log.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/runtime_log_screen.dart';

Widget _host() {
  return MaterialApp(
    theme: lightTheme,
    darkTheme: darkTheme,
    themeMode: ThemeMode.dark,
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const RuntimeLogScreen(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('runtime logs can be filtered to errors on a compact screen',
      (tester) async {
    AppLog.clear();
    AppLog.add('normal startup event');
    AppLog.add('network request failed', level: AppLogLevel.error);
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('运行日志'), findsOneWidget);
    expect(find.textContaining('normal startup event'), findsOneWidget);
    expect(find.textContaining('network request failed'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('runtime-log-errors-only')));
    await tester.pumpAndSettle();

    expect(find.textContaining('normal startup event'), findsNothing);
    expect(find.textContaining('network request failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
