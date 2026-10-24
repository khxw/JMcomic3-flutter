import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_download_card.dart';

const _channel = MethodChannel('methods');
const _captureKey = ValueKey('download-card-preview');
final _saveScreenshots =
    Platform.environment['DOWNLOAD_CARD_SCREENSHOTS'] == '1';

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': jsonEncode(data),
    });

Future<String> _createCover() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 180, 240),
    Paint()..color = const Color(0xFF9ACBD0),
  );
  canvas.drawCircle(
    const Offset(132, 58),
    28,
    Paint()..color = const Color(0xFFFFE59D),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(180, 240);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('build/download-card/fixture-cover.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return file.absolute.path;
}

List<DownloadAlbum> _albums() => [
      DownloadAlbum.fromJson({
        'id': 81001,
        'name': '海风经过旧车站',
        'author': ['夏日编辑部'],
        'tags': ['治愈', '旅行'],
        'works': ['海风经过旧车站'],
        'description': '正在下载。',
        'dl_status': 0,
        'image_count': 48,
        'dled_image_count': 31,
      }),
      DownloadAlbum.fromJson({
        'id': 81002,
        'name': '星海邮差与没有寄出的最后一封信',
        'author': ['远岸工作室'],
        'tags': ['科幻'],
        'works': ['星海邮差'],
        'description': '长标题测试。',
        'dl_status': 1,
        'image_count': 36,
        'dled_image_count': 36,
      }),
      DownloadAlbum.fromJson({
        'id': 81003,
        'name': '夜行列车',
        'author': ['月台'],
        'tags': ['悬疑'],
        'works': ['夜行列车'],
        'description': '失败状态测试。',
        'dl_status': 2,
        'image_count': 26,
        'dled_image_count': 9,
      }),
    ];

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
          textScaler: const TextScaler.linear(1.2),
        ),
        child: navigation!,
      );
    },
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('download cards stay readable and interactive on compact screens',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
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

    var tappedId = 0;
    final albums = _albums();
    await tester.pumpWidget(_host(RepaintBoundary(
      key: _captureKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('下载')),
        body: ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            for (final album in albums)
              ComicDownloadCard(
                album,
                key: Key('DOWNLOAD:${album.id}'),
                onTap: () => tappedId = album.id,
              ),
          ],
        ),
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.text('下载中'), findsOneWidget);
    expect(find.text('已下载'), findsOneWidget);
    expect(find.text('下载失败'), findsOneWidget);
    expect(find.text('31 / 48 张图片'), findsOneWidget);
    expect(find.text('65%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('download-card-81002')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('DOWNLOAD:81002')));
    await tester.pump();
    expect(tappedId, 81002);

    if (_saveScreenshots) {
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/download-card/download-cards-mobile.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
