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
    final properties = <String, String>{
      'remember_login_credentials': 'true',
      'remember_login_username': 'reader@example.com',
      'remember_login_password': 'secret',
    };
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      switch (request['method']) {
        case 'load_property':
          final key = request['params']?.toString() ?? '';
          return jsonEncode({
            'error_message': '',
            'response_data': properties[key] ?? '',
          });
        case 'save_property':
          final values = jsonDecode(request['params'] as String) as Map;
          properties[values['k'] as String] = values['v'] as String;
          break;
      }
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
    final remember =
        find.byKey(const ValueKey('first-login-remember-credentials'));
    expect(remember, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(remember).value, isTrue);
    expect(find.text('reader@example.com'), findsOneWidget);
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
