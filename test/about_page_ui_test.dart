import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/about_screen.dart';

const _methodsChannel = MethodChannel('methods');

void main() {
  testWidgets('about page exposes app information and project links',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_methodsChannel, (call) async {
      return jsonEncode({
        'error_message': '',
        'response_data': jsonEncode(''),
      });
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(_methodsChannel, null),
    );
    await initVersion();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AboutScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('about-app-info')), findsOneWidget);
    expect(find.byKey(const ValueKey('about-project-link')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('about-upstream-repository')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('about-update-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('about-license-entry')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('about-third-party-service')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('about-disclaimer')), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
