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
    final remember = find.byKey(const ValueKey('login-remember-credentials'));
    expect(remember, findsOneWidget);
    expect(tester.widget<Checkbox>(remember).value, isTrue);
    final rememberRow = find.byKey(const ValueKey('login-remember-row'));
    expect(
      find.descendant(of: rememberRow, matching: find.text('记住账号密码')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rememberRow, matching: find.text('使用协议')),
      findsOneWidget,
    );
    expect(
      tester
          .getCenter(
            find.descendant(
              of: rememberRow,
              matching: find.text('使用前请阅读'),
            ),
          )
          .dy,
      closeTo(
        tester
            .getCenter(
              find.descendant(
                of: rememberRow,
                matching: find.text('使用协议'),
              ),
            )
            .dy,
        1,
      ),
    );
    expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-guest')), findsOneWidget);
    expect(find.text('reader@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      '',
    );
    final submit = find.byKey(const ValueKey('login-submit'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();
    expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final dialog = find.byKey(const ValueKey('login-dialog'));
    final username = find.byKey(const ValueKey('login-username'));
    final password = find.byKey(const ValueKey('login-password'));
    await tester.tap(username);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final accountKeyboardDialogBottom = tester.getRect(dialog).bottom;

    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pump();
    await tester.ensureVisible(password);
    await tester.pumpAndSettle();
    await tester.tap(password);
    await tester.pumpAndSettle();

    final submitRect = tester.getRect(submit);
    expect(submitRect.top, greaterThanOrEqualTo(0));
    expect(submitRect.bottom, lessThanOrEqualTo(380));
    expect(
      tester.getRect(dialog).bottom,
      closeTo(accountKeyboardDialogBottom, 1),
    );
    expect(tester.takeException(), isNull);
  });
}
