import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    expect(find.text('Default directory'), findsOneWidget);
    expect(
      find.text('New downloads are saved directly to this directory'),
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
    expect(find.text('Default directory'), findsOneWidget);
    expect(
      find.text('New downloads are saved directly to this directory'),
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

  testWidgets('default download setting shows the effective backend path',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('methods'),
      (call) async {
        final request = jsonDecode(call.arguments as String) as Map;
        final response = switch (request['method']) {
          'get_download_directory_info' => jsonEncode({
              'custom_path': '',
              'effective_path': '/data/user/0/app/files/downloads',
              'default_path': '/data/user/0/app/files/downloads',
              'is_custom': false,
            }),
          'load_property' => '',
          _ => '',
        };
        return jsonEncode({
          'error_message': '',
          'response_data': response,
        });
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('methods'), null),
    );

    await refreshCustomDownloadDirectory();
    await tester.pumpWidget(_host(downloadDirectorySetting(), width: 320));
    await tester.pumpAndSettle();

    expect(
      find.text('/data/user/0/app/files/downloads'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
