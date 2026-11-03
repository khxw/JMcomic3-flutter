import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/first_login_screen.dart';

const _channel = MethodChannel('methods');

void main() {
  testWidgets('first login edits credentials inline without extra cards',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      return jsonEncode({
        'error_message': '',
        'response_data': jsonEncode(''),
      });
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
    await initVersion();

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const FirstLoginScreen(),
    ));
    await tester.pumpAndSettle();

    final username = find.byKey(const ValueKey('first-login-username'));
    final password = find.byKey(const ValueKey('first-login-password'));
    expect(username, findsOneWidget);
    expect(password, findsOneWidget);
    expect(find.byKey(const ValueKey('first-login-guest')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-project-links')), findsNothing);
    expect(find.text('Project links'), findsNothing);
    expect(
      find.widgetWithIcon(IconButton, Icons.explore_outlined),
      findsNothing,
    );
    expect(find.widgetWithIcon(IconButton, Icons.save), findsNothing);

    await tester.tap(username);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(username, 'reader@example.com');
    expect(find.text('reader@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
