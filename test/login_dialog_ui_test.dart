import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _channel = MethodChannel('methods');

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login dialog is compact and usable with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      switch (request['method']) {
        case 'load_username':
          return _response('reader@example.com');
        case 'load_password':
          return _response('secret');
        default:
          return _response('');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.6),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-login-dialog'),
                onPressed: () => loginDialog(context),
                child: const Text('登录'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-login-dialog')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-username')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-password')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-guest')), findsOneWidget);
    expect(find.text('reader@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pump();
    expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
