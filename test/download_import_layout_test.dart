import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/download_import_screen.dart';

const _captureKey = ValueKey('download-import-capture');
final _saveScreenshots =
    Platform.environment['DOWNLOAD_IMPORT_SCREENSHOTS'] == '1';

Widget _host() {
  return MaterialApp(
    theme: lightTheme,
    darkTheme: darkTheme,
    themeMode: ThemeMode.dark,
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => RepaintBoundary(
      key: _captureKey,
      child: child!,
    ),
    home: const DownloadImportScreen(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('download import actions stay readable on a compact screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('导入下载'), findsOneWidget);
    expect(find.text('导入已下载漫画'), findsOneWidget);
    expect(find.byKey(const ValueKey('download-import-file')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('download-import-folder')),
      findsOneWidget,
    );
    expect(find.text('JM.ZIP'), findsOneWidget);
    expect(find.text('JMI'), findsWidgets);

    for (final key in const [
      ValueKey('download-import-file'),
      ValueKey('download-import-folder'),
    ]) {
      final rect = tester.getRect(find.byKey(key));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
    expect(tester.takeException(), isNull);

    if (_saveScreenshots) {
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/download-import-layout/compact.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
