import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/download_and_export_to.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

Widget _host(Widget child, {double width = 390}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  test('download directory paths are trimmed and dequoted', () {
    expect(
      normalizeDownloadDirectoryPath('  "/storage/emulated/0/JM"  '),
      '/storage/emulated/0/JM',
    );
    expect(normalizeDownloadDirectoryPath(null), '');
  });

  testWidgets('download directory setting explains its scope', (tester) async {
    await tester.pumpWidget(_host(downloadDirectorySetting(), width: 320));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('download-directory-setting')),
      findsOneWidget,
    );
    expect(find.text('Custom download directory'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('App storage'), findsOneWidget);
    expect(
      find.text('New downloads are also saved to this folder'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact download directory summary stays on one line',
      (tester) async {
    await tester.pumpWidget(
      _host(downloadDirectorySetting(compact: true), width: 320),
    );
    await tester.pumpAndSettle();

    expect(find.text('Custom download directory'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('App storage'), findsOneWidget);
    expect(
      find.text('New downloads are also saved to this folder'),
      findsNothing,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('download-directory-setting')),
          )
          .height,
      lessThan(90),
    );
    expect(tester.takeException(), isNull);
  });
}
