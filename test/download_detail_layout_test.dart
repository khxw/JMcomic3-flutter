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
import 'package:jmcomic3/screens/download_album_screen.dart';

const _channel = MethodChannel('methods');
const _captureKey = ValueKey('download-detail-preview');
final _saveScreenshots =
    Platform.environment['DOWNLOAD_DETAIL_SCREENSHOTS'] == '1';

String _response(Object? data, {String error = ''}) => jsonEncode({
      'error_message': error,
      'response_data': data is String ? data : jsonEncode(data),
    });

Future<String> _createCover() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 240, 320),
    Paint()..color = const Color(0xFF9ACBD0),
  );
  canvas.drawCircle(
    const Offset(176, 72),
    32,
    Paint()..color = const Color(0xFFFFE8A3),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 320);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('build/download-detail/fixture-cover.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return file.absolute.path;
}

DownloadAlbum _album() => DownloadAlbum.fromJson({
      'id': 92001,
      'name': '山海之间的离线旅途',
      'author': ['山间工作室'],
      'tags': ['冒险', '友情', '自然'],
      'works': ['山海之间'],
      'description': '这是一份已经下载到本地的漫画内容，用于验证下载详情页布局。',
      'dl_square_cover_status': 1,
      'dl_3x4_cover_status': 1,
      'dl_status': 0,
      'image_count': 24,
      'dled_image_count': 15,
    });

DownloadCreate _create() => DownloadCreate.fromJson({
      'album': {
        'id': 92001,
        'name': '山海之间的离线旅途',
        'author': ['山间工作室'],
        'tags': ['冒险', '友情', '自然'],
        'works': ['山海之间'],
        'description': '离线下载内容。',
      },
      'chapters': [
        for (var index = 0; index < 8; index++)
          {
            'id': 94000 + index,
            'name': '第 ${index + 1} 话 · 山海旅途',
            'sort': '${index + 1}',
          },
      ],
    });

Widget _host(Widget child) {
  return MaterialApp(
    theme: lightTheme,
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

  testWidgets('download detail keeps progress, reading and chapters usable',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final coverPath = await tester.runAsync(_createCover);
    final album = _album();
    final create = _create();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      switch (request['method']) {
        case 'download_by_id':
          return _response(create.toJson());
        case 'download_album_by_id':
          return _response(album.toJson());
        case 'find_view_log':
          return _response({
            'id': album.id,
            'last_view_chapter_id': 94002,
            'last_view_page': 4,
          });
        case 'jm_3x4_cover':
          return _response(coverPath);
        default:
          return _response(null);
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(_host(
      RepaintBoundary(
        key: _captureKey,
        child: DownloadAlbumScreen(album),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('download-detail-hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('download-detail-read')), findsOneWidget);
    expect(find.text('继续阅读'), findsOneWidget);
    expect(find.textContaining('15 / 24'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('download-detail-chapters')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('download-detail-chapter-94000')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    if (_saveScreenshots) {
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/download-detail/download-detail-mobile.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
