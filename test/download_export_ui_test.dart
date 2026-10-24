import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/export_path.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/downloads_exporting_screen.dart';
import 'package:jmcomic3/screens/downloads_export_ui.dart';

const _channel = MethodChannel('methods');
const _captureKey = ValueKey('export-ui-preview');
final _saveScreenshots = Platform.environment['EXPORT_UI_SCREENSHOTS'] == '1';

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': jsonEncode(data),
    });

Future<String> _createCover() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 180, 240),
    Paint()..color = const Color(0xFFEFB6C8),
  );
  canvas.drawCircle(
    const Offset(132, 54),
    25,
    Paint()..color = const Color(0xFFFFE59D),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(180, 240);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('build/export-ui/fixture-cover.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return file.absolute.path;
}

List<DownloadAlbum> _albums() => [
      DownloadAlbum.fromJson({
        'id': 71001,
        'name': '雨后图书馆',
        'author': ['青苔'],
        'tags': ['校园', '治愈'],
        'works': ['雨后图书馆'],
        'description': '测试导出卡片。',
        'dl_status': 1,
        'image_count': 32,
        'dled_image_count': 32,
      }),
      DownloadAlbum.fromJson({
        'id': 71002,
        'name': '星海邮差与没有寄出的信',
        'author': ['远岸工作室'],
        'tags': ['旅行'],
        'works': ['星海邮差'],
        'description': '测试长标题布局。',
        'dl_status': 1,
        'image_count': 48,
        'dled_image_count': 48,
      }),
      DownloadAlbum.fromJson({
        'id': 71003,
        'name': '夜行列车',
        'author': ['月台'],
        'tags': ['悬疑'],
        'works': ['夜行列车'],
        'description': '测试下载状态。',
        'dl_status': 0,
        'image_count': 26,
        'dled_image_count': 12,
      }),
    ];

Widget _host(Widget child, {double textScale = 1}) {
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
          textScaler: TextScaler.linear(textScale),
        ),
        child: navigation!,
      );
    },
    home: child,
  );
}

class _SelectionHarness extends StatefulWidget {
  const _SelectionHarness();

  @override
  State<_SelectionHarness> createState() => _SelectionHarnessState();
}

class _SelectionHarnessState extends State<_SelectionHarness> {
  final Set<int> _selected = {71001};

  @override
  Widget build(BuildContext context) {
    final albums = _albums();
    return Scaffold(
      appBar: AppBar(title: const Text('批量导出')),
      body: DownloadExportSelectionView(
        albums: albums,
        selected: _selected,
        modeLabel: '包含未完成任务',
        onToggle: (album) {
          setState(() {
            if (!_selected.add(album.id)) {
              _selected.remove(album.id);
            }
          });
        },
        onSelectAll: () {
          setState(() {
            _selected
              ..clear()
              ..addAll(albums.map((album) => album.id));
          });
        },
        onClear: () {
          setState(_selected.clear);
        },
        onContinue: () {},
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('batch export selection is usable on compact dark layouts',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final coverPath = await tester.runAsync(_createCover);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      if (request['method'] == 'jm_3x4_cover') {
        return _response(coverPath);
      }
      return _response(null);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(_host(
      const RepaintBoundary(
        key: _captureKey,
        child: _SelectionHarness(),
      ),
      textScale: 1.25,
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('batch-export-summary')),
      findsOneWidget,
    );
    expect(find.text('已选择 1 本'), findsWidgets);
    expect(
      find.byKey(const ValueKey('batch-export-continue')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('batch-export-album-71002')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('batch-export-album-71002')),
    );
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 本'), findsWidgets);
    expect(tester.takeException(), isNull);

    if (_saveScreenshots) {
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/export-ui/export-selection-mobile.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('batch export formats remain scannable on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      if (request['method'] == 'load_property') {
        return _response(r'C:\TestExports');
      }
      return _response(null);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
    await initExportPath();

    await tester.pumpWidget(_host(
      const RepaintBoundary(
        key: _captureKey,
        child: DownloadsExportingScreen(idList: [71001, 71002]),
      ),
      textScale: 1.2,
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('batch-export-format-list')),
      findsOneWidget,
    );
    expect(find.text('漫画压缩包'), findsOneWidget);
    expect(find.text('电子书'), findsOneWidget);
    expect(find.text('保存位置与选项'), findsOneWidget);
    expect(find.text(r'C:\TestExports'), findsOneWidget);
    expect(tester.takeException(), isNull);

    if (_saveScreenshots) {
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/export-ui/export-formats-mobile.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
