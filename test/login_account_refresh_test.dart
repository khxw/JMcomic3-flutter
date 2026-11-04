import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/daily_sign.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/user_screen.dart';

const _channel = MethodChannel('methods');

Map<String, Object> _selfInfo(int level) => {
      'uid': 42,
      'username': 'reader',
      'email': '',
      'emailverified': '',
      'photo': '',
      'fname': '',
      'gender': '',
      'message': '',
      'coin': 12,
      'album_favorites': 0,
      's': '',
      'level_name': 'Reader',
      'level': level,
      'nextLevelExp': 100,
      'exp': '20',
      'expPercent': 20.0,
      'badges': <Object>[],
      'album_favorites_max': 100,
    };

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login refreshes account info and daily sign status',
      (tester) async {
    var dailyCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (request['method']) {
        case 'login':
          return _response(_selfInfo(1));
        case 'pre_login':
          return _response({
            'pre_set': true,
            'pre_login': true,
            'message': '',
            'self_info': _selfInfo(9),
          });
        case 'daily':
          dailyCalls++;
          return _response('Signed in');
        case 'favorite':
          return _response({
            'total': 0,
            'count': 0,
            'list': <Object>[],
            'folder_list': <Object>[],
          });
        default:
          return _response('');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      dailySignStatus = DailySignStatus.unchecked;
    });

    await enterGuestMode();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const UserScreen(),
    ));
    await tester.pumpAndSettle();

    await login(
      'reader',
      'password',
      tester.element(find.byType(UserScreen)),
      rememberCredentials: false,
    );
    await tester.pumpAndSettle();

    expect(loginStatus, LoginStatus.loginSuccess);
    expect(selfInfo.level, 9);
    expect(dailyCalls, 1);
    expect(dailySignStatus, DailySignStatus.signed);
    expect(find.text('Signed in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
