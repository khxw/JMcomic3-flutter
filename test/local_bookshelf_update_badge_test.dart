import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/basic/local_bookshelf.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/bookshelf_screen.dart';

const _channel = MethodChannel('methods');

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });

Map<String, Object> _album(int updateAt) => {
      'id': 7,
      'name': 'Comic',
      'author': ['Author'],
      'images': ['cover.webp'],
      'description': '',
      'total_views': 1,
      'likes': 1,
      'series': <Object>[],
      'series_id': 1,
      'comment_total': 0,
      'tags': <Object>[],
      'works': <Object>[],
      'related_list': <Object>[],
      'liked': false,
      'is_favorite': false,
      'update_at': updateAt,
      'addtime': 100,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('folder shows an update badge until the comic is opened',
      (tester) async {
    final properties = <String, String>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (request['method']) {
        case 'load_property':
          return _response(properties['${request['params']}'] ?? '');
        case 'save_property':
          final values =
              jsonDecode(request['params'] as String) as Map<String, dynamic>;
          properties[values['k'] as String] = values['v'] as String;
          return _response('');
        case 'album':
          return _response(_album(200));
        default:
          return _response('');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      resetLocalBookshelfMemory();
    });

    resetLocalBookshelfMemory();
    await enterGuestMode();
    await toggleLocalBookshelf(
      ComicBasic(
        id: 7,
        author: 'Author',
        description: '',
        name: 'Comic',
        image: 'cover.webp',
        updateAt: 100,
      ),
      group: 'Reading',
    );
    await refreshLocalBookshelfUpdates(force: true);

    expect(localBookshelfItems.single.hasUpdate, isTrue);
    expect(localBookshelfUpdateCount('Reading'), 1);

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: BookshelfScreen(),
    ));
    await tester.pumpAndSettle();

    final badge = find.byKey(const ValueKey('bookshelf-folder-update-Reading'));
    expect(badge, findsOneWidget);

    await markLocalBookshelfItemSeen(7);
    await tester.pumpAndSettle();
    expect(localBookshelfItems.single.hasUpdate, isFalse);
    expect(badge, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
