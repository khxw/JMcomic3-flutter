import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/login.dart' as login_config;
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/bookshelf_screen.dart';
import 'package:jmcomic3/screens/components/comic_list.dart';

const _channel = MethodChannel('methods');

Map<String, dynamic> _comicFixture() => {
      'id': 7,
      'author': 'author',
      'description': '',
      'name': 'online comic',
      'image': '7.jpg',
      'category': {'id': '1', 'title': 'category'},
      'category_sub': {'id': '2', 'title': 'subcategory'},
      'update_at': 0,
      'addtime': 0,
    };

Map<String, dynamic> _selfInfoFixture() => {
      'uid': 1,
      'username': 'reader',
      'email': '',
      'emailverified': '',
      'photo': '',
      'fname': '',
      'gender': '',
      'message': '',
      'coin': 0,
      'album_favorites': 1,
      's': 'session',
      'level_name': '',
      'level': 1,
      'nextLevelExp': 0,
      'exp': '0',
      'expPercent': 0.0,
      'badges': <dynamic>[],
      'album_favorites_max': 0,
    };

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });

Widget _host() {
  return const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: BookshelfScreen(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('online favorites only appear after signing in', (tester) async {
    final pendingCover = Completer<String>();
    final properties = <String, String>{
      'pager_controller_mode': PagerControllerMode.pager.toString(),
      'pager_view_mode': PagerViewMode.cover.toString(),
      'pager_cover_rate': PagerCoverRate.rate3x4.toString(),
      'pager_column_number': '4',
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final payload = jsonDecode(call.arguments as String) as Map;
      final method = payload['method'] as String;
      switch (method) {
        case 'load_property':
          return _response(properties[payload['params']] ?? '');
        case 'save_property':
          final values = jsonDecode(payload['params'] as String) as Map;
          properties[values['k'] as String] = values['v'] as String;
          return _response('');
        case 'login':
          return _response(_selfInfoFixture());
        case 'favorite':
          return _response({
            'total': 1,
            'count': 1,
            'list': [_comicFixture()],
            'folder_list': <dynamic>[],
          });
        case 'favorites':
          return _response({
            'total': 1,
            'count': 1,
            'list': [_comicFixture()],
            'folder_list': <dynamic>[],
          });
        case 'jm_3x4_cover':
          return pendingCover.future;
        default:
          return _response('');
      }
    });
    addTearDown(() async {
      if (!pendingCover.isCompleted) pendingCover.complete('');
      await tester.pumpWidget(const SizedBox.shrink());
      messenger.setMockMethodCallHandler(_channel, null);
      login_config.favData = [];
    });

    await initPagerControllerMode();
    await initPagerViewMode();
    await initPagerCoverRate();
    await initPagerColumnCount();
    await login_config.enterGuestMode();

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bookshelf-section-online')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('bookshelf-local-content')),
      findsOneWidget,
    );

    await login_config.login(
      'reader',
      'password',
      tester.element(find.byType(BookshelfScreen)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bookshelf-section-online')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('bookshelf-section-online')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bookshelf-online-content')),
      findsOneWidget,
    );
    final onlineList = tester.widget<ComicList>(find.byType(ComicList));
    expect(onlineList.data.single.name, 'online comic');
    expect(tester.takeException(), isNull);
  });
}
