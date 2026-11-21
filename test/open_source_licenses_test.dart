import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jmcomic3/basic/open_source_licenses.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/open_source_license_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registers bundled native and vendored component licenses', () async {
    await ensureOpenSourceLicensesRegistered();
    final packages = <String>{};
    await for (final license in LicenseRegistry.licenses) {
      packages.addAll(license.packages);
    }

    expect(packages, contains('Tencent ncnn'));
    expect(packages, contains('waifu2x-ncnn-vulkan'));
    expect(packages, contains('zoomable_positioned_list'));
    expect(
      packages,
      contains('zoomable_positioned_list Fuchsia components'),
    );
  });

  testWidgets('license screen supports search and license details',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final loaded = await tester.runAsync(() => loadGroupedLicenses());
    expect(loaded, contains('Tencent ncnn'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OpenSourceLicenseScreen(applicationVersion: 'test'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byKey(const ValueKey('open-source-license-page')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Core components'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('license-featured-tencent-ncnn')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('license-search')),
      'ncnn',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('license-package-tencent-ncnn')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('license-package-tencent-ncnn')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const ValueKey('license-detail-page')),
      findsOneWidget,
    );
    expect(find.textContaining('Tencent is pleased'), findsOneWidget);
  });
}
