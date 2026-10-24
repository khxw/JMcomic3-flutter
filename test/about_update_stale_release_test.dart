import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/about_screen.dart';

const _channel = MethodChannel('methods');

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': jsonEncode(data),
    });

Widget _host(Widget child) {
  return MaterialApp(
    theme: darkTheme,
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an older online release is never shown as latest',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final properties = <String, String>{
      'latestVersionRepoCache': 'khxw/JMcomic3-flutter',
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final method = request['method'];
      final params = request['params']?.toString() ?? '';
      switch (method) {
        case 'load_property':
          return _response(properties[params] ?? '');
        case 'save_property':
          final values = jsonDecode(params) as Map;
          properties[values['k'] as String] = values['v'] as String;
          return _response('');
        case 'http_get':
          return _response({
            'tag_name': 'v1.7.47+76',
            'name': 'JMComic3 Mod v1.7.47+76',
            'body': '## 旧版本\n\n- 不应显示为最新版本',
          });
        default:
          return _response('');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
    await initVersion();

    await tester.pumpWidget(_host(const AboutScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('about-latest-version')),
        matching: find.text(currentVersion()),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('about-release-notes')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
