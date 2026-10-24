import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/about_screen.dart';

const _channel = MethodChannel('methods');
const _captureKey = ValueKey('about-update-preview');
final _saveScreenshots =
    Platform.environment['ABOUT_UPDATE_SCREENSHOTS'] == '1';

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
    builder: (context, navigation) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.25),
        ),
        child: navigation!,
      );
    },
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'update page shows status, action and release notes on compact UI',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
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
            'tag_name': 'v9.9.9',
            'name': 'JMComic3 Mod v9.9.9',
            'body': '## 更新内容\n\n- 新的下载管理界面\n- 阅读器性能优化',
          });
        default:
          return _response('');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
    await initVersion();

    await tester.pumpWidget(_host(RepaintBoundary(
      key: _captureKey,
      child: const AboutScreen(),
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about-update-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('about-app-icon')), findsOneWidget);
    expect(
      find.image(
        const AssetImage('lib/assets/app_icon_background.png'),
      ),
      findsOneWidget,
    );
    expect(
      find.image(
        const AssetImage('lib/assets/app_icon_foreground.png'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('about-update-status')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('about-current-version')),
        matching: find.text(currentVersion()),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('about-latest-version')),
        matching: find.text('v9.9.9'),
      ),
      findsOneWidget,
    );
    expect(find.text('发现新版本 v9.9.9'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('about-check-update')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('about-download-update')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('about-release-notes')), findsOneWidget);
    expect(find.textContaining('新的下载管理界面'), findsOneWidget);
    expect(tester.takeException(), isNull);

    if (_saveScreenshots) {
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/about-update/about-update-mobile.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
