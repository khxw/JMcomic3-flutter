import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/configs/user_agreement.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/user_agreement_screen.dart';

const _channel = MethodChannel('methods');

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': jsonEncode(data),
    });

Widget _host({
  required GlobalKey<NavigatorState> navigatorKey,
  double textScale = 1,
}) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    theme: darkTheme,
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      );
    },
    home: const Scaffold(body: SizedBox.expand()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first-run agreement requires explicit consent', (tester) async {
    final properties = <String, String>{};
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
        default:
          return _response('');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_host(navigatorKey: navigatorKey));
    navigatorKey.currentState!.push(
      MaterialPageRoute<bool>(
        builder: (_) => const UserAgreementScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agreement-welcome-step')),
      findsOneWidget,
    );
    expect(find.text('JMComic3 Mod'), findsOneWidget);
    expect(find.text('下一步将展示用户协议'), findsNothing);
    expect(
      find.byKey(const ValueKey('agreement-terms-step')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('agreement-welcome-continue')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agreement-terms-step')),
      findsOneWidget,
    );
    expect(find.text('用户协议'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('agreement-accept')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('agreement-accept-checkbox')),
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('agreement-accept')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('agreement-accept')));
    await tester.pumpAndSettle();

    expect(find.byType(UserAgreementScreen), findsNothing);
    expect(
      properties['accepted_user_agreement_version'],
      userAgreementVersion,
    );
    expect(await hasAcceptedCurrentUserAgreement(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agreement layout remains usable on a compact large-text screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _host(navigatorKey: navigatorKey, textScale: 1.5),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<bool>(
        builder: (_) => const UserAgreementScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('agreement-welcome-continue')),
    );
    await tester.pumpAndSettle();

    expect(find.text('同意并继续'), findsOneWidget);
    expect(find.byKey(const ValueKey('agreement-exit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared agreement sheet is scrollable and compact-safe',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _host(navigatorKey: navigatorKey, textScale: 1.35),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: Builder(
            builder: (buttonContext) => Center(
              child: FilledButton(
                onPressed: () => showLoginAgreementBottomSheet(buttonContext),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('user-agreement-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('user-agreement-scroll')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agreement-summary-card')),
      findsOneWidget,
    );
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.textContaining(userAgreementVersion), findsOneWidget);
    expect(find.text('本地数据'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-agreement-got-it')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('user-agreement-got-it')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('user-agreement-sheet')),
      findsNothing,
    );
  });
}
