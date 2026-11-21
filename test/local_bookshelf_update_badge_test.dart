import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/basic/local_bookshelf.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/bookshelf_screen.dart';

const _channel = MethodChannel('methods');

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });

Map<String, Object?> _album({
  int? updateAt,
  List<Map<String, String>> series = const [],
}) {
  final album = <String, Object?>{
    'id': 7,
    'name': 'Comic',
    'author': ['Author'],
    'images': ['cover.webp'],
    'description': '',
    'total_views': 1,
    'likes': 1,
    'series': series,
    'series_id': 1,
    'comment_total': 0,
    'tags': <Object>[],
    'works': <Object>[],
    'related_list': <Object>[],
    'liked': false,
    'is_favorite': false,
    'addtime': 100,
  };
  if (updateAt != null) album['update_at'] = updateAt;
  return album;
}

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
          return _response(_album(updateAt: 200));
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

    await initPagerViewMode();
    await initPagerCoverRate();
    await initPagerColumnCount();
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: BookshelfScreen(),
    ));
    await tester.pumpAndSettle();

    final badge = find.byKey(const ValueKey('bookshelf-folder-update-Reading'));
    expect(badge, findsOneWidget);
    expect(tester.getSize(badge), const Size(7, 7));
    final folderRect =
        tester.getRect(find.byKey(const ValueKey('bookshelf-folder-Reading')));
    final badgeRect = tester.getRect(badge);
    expect(folderRect.right - badgeRect.right, closeTo(9, 1));
    expect(badgeRect.top - folderRect.top, closeTo(9, 1));
    expect(
      find.descendant(of: badge, matching: find.byType(Text)),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('bookshelf-folder-Reading')));
    await tester.pumpAndSettle();
    final comicBadge = find.byKey(const ValueKey('bookshelf-comic-update-7'));
    expect(comicBadge, findsOneWidget);
    expect(tester.getSize(comicBadge), const Size(7, 7));

    await tester.tap(comicBadge);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(localBookshelfItems.single.hasUpdate, isTrue);

    await markLocalBookshelfItemSeen(7);
    expect(localBookshelfItems.single.hasUpdate, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh resolves update time from the latest chapter',
      (tester) async {
    final properties = <String, String>{};
    final requests = <Map<String, dynamic>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      requests.add(request);
      switch (request['method']) {
        case 'load_property':
          return _response(properties['${request['params']}'] ?? '');
        case 'save_property':
          final values =
              jsonDecode(request['params'] as String) as Map<String, dynamic>;
          properties[values['k'] as String] = values['v'] as String;
          return _response('');
        case 'album':
          return _response(_album(
            series: [
              {'id': '7', 'name': 'First', 'sort': '1'},
              {'id': '9', 'name': 'Latest', 'sort': '2'},
            ],
          ));
        case 'chapter':
          return _response({
            'id': 9,
            'series': <Object>[],
            'tags': '',
            'name': 'Latest',
            'images': <Object>[],
            'series_id': 7,
            'is_favorite': false,
            'liked': false,
            'addtime': 200,
          });
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

    expect(localBookshelfItems.single.comic.updateAt, 200);
    expect(localBookshelfItems.single.hasUpdate, isTrue);
    expect(
      requests
          .where((request) => request['method'] == 'chapter')
          .single['params'],
      '9',
    );
    expect(tester.takeException(), isNull);
  });
}
