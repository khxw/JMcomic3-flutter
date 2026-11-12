import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart' as native;
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

String _errorResponse(String message) => jsonEncode({
      'error_message': message,
      'response_data': '',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login refreshes account info and daily sign status',
      (tester) async {
    var dailyCalls = 0;
    var preLoginCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (request['method']) {
        case 'login':
          return _response(_selfInfo(1));
        case 'pre_login':
          preLoginCalls++;
          return _response({
            'pre_set': true,
            'pre_login': true,
            'message': '',
            'self_info': _selfInfo(preLoginCalls >= 2 ? 10 : 9),
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
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: UserScreen(),
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
    expect(selfInfo.level, 10);
    expect(dailyCalls, 1);
    expect(dailySignStatus, DailySignStatus.signed);
    expect(find.text('Signed in'), findsOneWidget);

    final callsBeforeResume = preLoginCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(preLoginCalls, callsBeforeResume);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged account details do not broadcast another refresh',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (request['method']) {
        case 'pre_login':
          return _response({
            'pre_set': true,
            'pre_login': true,
            'message': '',
            'self_info': _selfInfo(10),
          });
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
    });

    await enterGuestMode();
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: UserScreen(),
    ));
    await initLogin(tester.element(find.byType(UserScreen)));
    await tester.pumpAndSettle();

    final accountBeforeRefresh = selfInfo;
    var loginEvents = 0;
    void onLoginEvent(_) => loginEvents++;
    loginEvent.subscribe(onLoginEvent);
    addTearDown(() => loginEvent.unsubscribe(onLoginEvent));

    expect(await refreshSelfInfo(), isTrue);

    expect(identical(selfInfo, accountBeforeRefresh), isTrue);
    expect(loginEvents, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive profile does not refresh when the app resumes',
      (tester) async {
    var preLoginCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      if (request['method'] == 'pre_login') {
        preLoginCalls++;
        return _response({
          'pre_set': true,
          'pre_login': true,
          'message': '',
          'self_info': _selfInfo(10),
        });
      }
      if (request['method'] == 'favorite') {
        return _response({
          'total': 0,
          'count': 0,
          'list': <Object>[],
          'folder_list': <Object>[],
        });
      }
      return _response('');
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    await enterGuestMode();
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: TickerMode(
        enabled: false,
        child: UserScreen(),
      ),
    ));
    await initLogin(tester.element(find.byType(UserScreen)));
    await tester.pumpAndSettle();

    final callsBeforeResume = preLoginCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(preLoginCalls, callsBeforeResume);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired account requests refresh login and retry once',
      (tester) async {
    var favoriteCalls = 0;
    var refreshCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (request['method']) {
        case 'favorite':
          favoriteCalls++;
          if (favoriteCalls == 1) {
            return _errorResponse('JM API error 0: 请先登录');
          }
          return _response({
            'total': 0,
            'count': 0,
            'list': <Object>[],
            'folder_list': <Object>[],
          });
        case 'refresh_login':
          refreshCalls++;
          return _response({'refreshed': true, 'self_info': _selfInfo(9)});
        default:
          return _response('');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
    });

    final favorite = await native.methods.favorite();

    expect(favorite.folderList, isEmpty);
    expect(favoriteCalls, 2);
    expect(refreshCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid JSON switches API route and retries the request',
      (tester) async {
    var favoriteCalls = 0;
    var rotations = 0;
    native.Methods.apiHostRecoveryHandler = () async {
      rotations++;
      return true;
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      if (request['method'] == 'favorite') {
        favoriteCalls++;
        if (favoriteCalls == 1) {
          return _errorResponse(
              'JSON error: expected value at line 1 column 1');
        }
        return _response({
          'total': 0,
          'count': 0,
          'list': <Object>[],
          'folder_list': <Object>[],
        });
      }
      return _response('');
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      native.Methods.apiHostRecoveryHandler = null;
    });

    final favorite = await native.methods.favorite();

    expect(favorite.folderList, isEmpty);
    expect(favoriteCalls, 2);
    expect(rotations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image HTTP failures switch CDN route and retry', (tester) async {
    var imageCalls = 0;
    var rotations = 0;
    native.Methods.cdnHostRecoveryHandler = (_) async {
      rotations++;
      return true;
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      if (request['method'] == 'jm_page_image') {
        imageCalls++;
        if (imageCalls == 1) {
          return _errorResponse('HTTP 500:');
        }
        return _response('/cache/page.webp');
      }
      return _response('');
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      native.Methods.cdnHostRecoveryHandler = null;
    });

    final path = await native.methods.jmPageImage(42, '001.webp');

    expect(path, '/cache/page.webp');
    expect(imageCalls, 2);
    expect(rotations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read API HTTP 500 switches route and retries', (tester) async {
    var dailyCalls = 0;
    var rotations = 0;
    native.Methods.apiHostRecoveryHandler = () async {
      rotations++;
      return true;
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      if (request['method'] == 'daily') {
        dailyCalls++;
        if (dailyCalls == 1) {
          return _errorResponse('HTTP 500:');
        }
        return _response('Signed in');
      }
      return _response('');
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      native.Methods.apiHostRecoveryHandler = null;
    });

    final result = await native.methods.daily(42);

    expect(result, 'Signed in');
    expect(dailyCalls, 2);
    expect(rotations, 1);
    expect(tester.takeException(), isNull);
  });
}
