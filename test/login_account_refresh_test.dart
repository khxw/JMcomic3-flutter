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

  testWidgets('login refreshes account info without automatic sign-in',
      (tester) async {
    var dailyCalls = 0;
    var dailyStatusCalls = 0;
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
        case 'daily_status':
          dailyStatusCalls++;
          return _response({
            'record': [
              [
                {
                  'date': DateTime.now().day.toString().padLeft(2, '0'),
                  'signed': true,
                  'bonus': false,
                },
              ],
            ],
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
    expect(selfInfo.level, 9);
    expect(dailyCalls, 0);
    expect(dailyStatusCalls, greaterThanOrEqualTo(1));
    expect(dailySignStatus, DailySignStatus.signed);
    expect(find.text('Signed in'), findsOneWidget);
    final statusCallsBeforeRetry = dailyStatusCalls;
    await refreshDailySignStatus();
    expect(dailyStatusCalls, statusCallsBeforeRetry);

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

  testWidgets('profile refresh requires a pull gesture and respects cooldown',
      (tester) async {
    var preLoginCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (request['method']) {
        case 'pre_login':
          preLoginCalls++;
          return _response({
            'pre_set': true,
            'pre_login': true,
            'message': '',
            'self_info': _selfInfo(preLoginCalls >= 2 ? 10 : 1),
          });
        case 'daily_status':
          return _response({'record': <Object>[]});
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
      resetDailySignStatus();
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

    expect(preLoginCalls, 1);
    expect(selfInfo.level, 1);

    final scrollable = find.byType(SingleChildScrollView).first;
    await tester.drag(scrollable, const Offset(0, 360));
    await tester.pumpAndSettle();

    expect(preLoginCalls, 2);
    expect(selfInfo.level, 10);

    await tester.drag(scrollable, const Offset(0, 360));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    expect(preLoginCalls, 2);
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
    native.Methods.apiHostRecoveryHandler = (observedVersion) async {
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

  testWidgets('HTML 404 login switches API route and retries', (tester) async {
    var loginCalls = 0;
    var rotations = 0;
    native.Methods.apiHostRecoveryHandler = (observedVersion) async {
      rotations++;
      return true;
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      if (request['method'] == 'login') {
        loginCalls++;
        if (loginCalls == 1) {
          return _errorResponse(
            'HTTP 404: <html><head><title>404 Not Found</title></head>'
            '<body><center><h1>404 Not Found</h1></center>'
            '<hr><center>nginx</center></body></html>',
          );
        }
        return _response(_selfInfo(7));
      }
      return _response('');
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      native.Methods.apiHostRecoveryHandler = null;
    });

    final selfInfo = await native.methods.login('reader', 'password');

    expect(selfInfo.username, 'reader');
    expect(selfInfo.level, 7);
    expect(loginCalls, 2);
    expect(rotations, 1);
  });

  testWidgets('HTML 404 pre-login switches API route and retries',
      (tester) async {
    var preLoginCalls = 0;
    var rotations = 0;
    native.Methods.apiHostRecoveryHandler = (observedVersion) async {
      rotations++;
      return true;
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      if (request['method'] == 'pre_login') {
        preLoginCalls++;
        if (preLoginCalls == 1) {
          return _errorResponse(
            'HTTP 404: <html><head><title>404 Not Found</title></head>'
            '<body><center><h1>404 Not Found</h1></center></body></html>',
          );
        }
        return _response({
          'pre_set': true,
          'pre_login': true,
          'message': '',
          'self_info': _selfInfo(7),
        });
      }
      return _response('');
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      native.Methods.apiHostRecoveryHandler = null;
    });

    final result = await native.methods.preLogin();

    expect(result.preLogin, isTrue);
    expect(result.selfInfo?.level, 7);
    expect(preLoginCalls, 2);
    expect(rotations, 1);
  });

  testWidgets('legacy pre-login HTML messages are sanitized', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      if (request['method'] == 'pre_login') {
        return _response({
          'pre_set': true,
          'pre_login': false,
          'message': 'HTTP 404: <html><body>nginx 404 Not Found</body></html>',
          'self_info': null,
        });
      }
      return _response('');
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

    expect(
      loginMessage,
      'The login API route is unavailable. Try again shortly.',
    );
    expect(loginMessage, isNot(contains('<html>')));
  });

  testWidgets('login route errors do not expose raw HTML', (tester) async {
    native.Methods.apiHostRecoveryHandler = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      if (request['method'] == 'login') {
        return _errorResponse(
          'HTTP 404: <html><body><center>nginx 404 Not Found</center></body>'
          '</html>',
        );
      }
      return _response('');
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
    });

    await expectLater(
      native.methods.login('reader', 'password'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '登录接口线路不可用，请切换 API 分流后重试。',
        ),
      ),
    );
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
    native.Methods.apiHostRecoveryHandler = (observedVersion) async {
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
