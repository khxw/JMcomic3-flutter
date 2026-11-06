import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/login.dart' as login;
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/comments_screen.dart';

const _channel = MethodChannel('methods');
const _captureKey = ValueKey('comments-layout-preview');
final _saveScreenshots = Platform.environment['COMMENTS_SCREENSHOTS'] == '1';

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': jsonEncode(data),
    });

Map<String, dynamic> _comment({
  required int cid,
  required String nickname,
  required String content,
  int likes = 0,
  List<Map<String, dynamic>> replys = const [],
}) {
  return {
    'AID': 42,
    'CID': cid,
    'UID': 100 + cid,
    'username': nickname,
    'nickname': nickname,
    'likes': likes,
    'gender': 'F',
    'update_at': '1775974304',
    'addtime': '刚刚',
    'parent_CID': 0,
    'expinfo': {
      'level_name': 'Lv.$cid',
      'level': cid,
      'nextLevelExp': 100,
      'exp': '66',
      'expPercent': 66.6,
      'uid': 100 + cid,
      'badges': <Object>[],
    },
    'name': '一部名字比较长的测试漫画',
    'content': content,
    'photo': '?v=0?v=',
    'spoiler': 0,
    'replys': replys,
  };
}

Map<String, dynamic> _selfInfo() => {
      'uid': 42,
      'username': 'Comment reader',
      'email': 'reader@example.invalid',
      'emailverified': 'yes',
      'photo': '?v=0?v=',
      'fname': 'Reader',
      'gender': '',
      'message': '',
      'coin': 0,
      'album_favorites': 0,
      's': '',
      'level_name': 'Reader',
      'level': 1,
      'nextLevelExp': 100,
      'exp': '0',
      'expPercent': 0.0,
      'badges': <Object>[],
      'album_favorites_max': 100,
    };

Widget _host(Widget child) {
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
    home: child,
  );
}

Future<void> _loadPreviewFonts(WidgetTester tester) async {
  if (!_saveScreenshots) return;
  await tester.runAsync(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in ['LayoutPreview', 'Roboto']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
    final config =
        jsonDecode(await File('.dart_tool/package_config.json').readAsString())
            as Map;
    final sdk = Uri.parse(config['flutterRoot'] as String).toFilePath();
    final icons = File(
        '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')
            ..addFont(
                Future.value(ByteData.sublistView(await icons.readAsBytes()))))
          .load();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('discussion cards remain readable on a compact screen',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final reply = _comment(
      cid: 2,
      nickname: '回复用户',
      content: '回复内容也使用相同的圆角卡片，并保持清晰的行距。',
    );
    final comments = [
      _comment(
        cid: 1,
        nickname: '一位昵称很长的漫画读者',
        content: '这是一条用于验证新版评论区布局的较长评论。内容应当有足够的行距，作者、等级、时间和互动信息也不应该挤在一起。',
        likes: 18,
        replys: [reply],
      ),
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      if (request['method'] == 'forum') {
        return _response({'total': 1, 'list': comments});
      }
      return _response('');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await _loadPreviewFonts(tester);
    await tester.pumpWidget(_host(const CommentsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('讨论区'), findsOneWidget);
    expect(find.text('全部评论'), findsOneWidget);
    expect(find.text('我的评论'), findsOneWidget);
    expect(find.text('一位昵称很长的漫画读者'), findsOneWidget);
    expect(find.textContaining('新版评论区布局'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(tester.takeException(), isNull);

    if (_saveScreenshots) {
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/comments-layout/comments-mobile.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('comment like uses the bridge once and updates the heart',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requests = <Map<String, dynamic>>[];
    final comments = [
      _comment(
        cid: 456,
        nickname: '点赞测试用户',
        content: '点击心形后应调用后端，并且不能重复提交。',
        likes: 3,
      ),
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      requests.add(Map<String, dynamic>.from(request));
      switch (request['method']) {
        case 'load_property':
          return _response('');
        case 'pre_login':
          return _response({
            'pre_set': true,
            'pre_login': true,
            'message': '',
            'self_info': _selfInfo(),
          });
        case 'favorite':
          return _response({
            'total': 0,
            'count': 0,
            'list': <Object>[],
            'folder_list': <Object>[],
          });
        case 'pro_info_all':
          return _response({
            'pro_info_af': {'is_pro': true, 'expire': 4102444800},
            'pro_info_pat': {'is_pro': true},
          });
        case 'forum':
          return _response({'total': 1, 'list': comments});
        case 'like_comment':
          return _response({
            'status': 'ok',
            'msg': '勿短時間重複留言',
            'upstream_limited': true,
          });
        default:
          return _response('');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(_host(const SizedBox()));
    await login.initLogin(tester.element(find.byType(SizedBox)));
    await tester.pumpAndSettle();
    expect(login.loginStatus, login.LoginStatus.loginSuccess);

    await tester.pumpWidget(_host(const CommentsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();

    final likeCalls =
        requests.where((request) => request['method'] == 'like_comment');
    expect(likeCalls, hasLength(1));
    expect(likeCalls.single['params'], '456');
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.textContaining('已在本机点赞'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pumpAndSettle();
    expect(
      requests.where((request) => request['method'] == 'like_comment'),
      hasLength(1),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
