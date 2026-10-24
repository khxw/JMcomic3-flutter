import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

Widget _host(Widget home) {
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
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.35),
        ),
        child: child!,
      );
    },
    home: home,
  );
}

void main() {
  testWidgets('choice dialog is compact, scrollable and returns a value',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? selected;
    await tester.pumpWidget(_host(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                selected = await chooseListDialog<String>(
                  context,
                  values: const ['简洁模式', '完整模式', '自定义模式'],
                  title: '选择显示模式',
                  tips: '可随时在设置中修改。',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-choice-dialog')), findsOneWidget);
    expect(find.text('选择显示模式'), findsOneWidget);
    expect(find.text('可随时在设置中修改。'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('完整模式'));
    await tester.pumpAndSettle();
    expect(selected, '完整模式');
  });

  testWidgets('text input dialog returns edited content', (tester) async {
    String? result;
    await tester.pumpWidget(_host(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                result = await displayTextInputDialog(
                  context,
                  title: '输入名称',
                  hint: '请输入内容',
                  desc: '名称会保存在本机。',
                  src: '原名称',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('app-text-input-dialog')),
      findsOneWidget,
    );
    expect(find.text('名称会保存在本机。'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('app-text-input-field')),
      '新名称',
    );
    await tester.tap(find.byKey(const ValueKey('app-text-input-confirm')));
    await tester.pumpAndSettle();
    expect(result, '新名称');
  });

  testWidgets('confirmation dialog has clear cancel and confirm actions',
      (tester) async {
    bool? confirmed;
    await tester.pumpWidget(_host(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                confirmed = await confirmDialog(
                  context,
                  '确认操作',
                  '此操作无法撤销，请确认是否继续。',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-confirm-dialog')), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
