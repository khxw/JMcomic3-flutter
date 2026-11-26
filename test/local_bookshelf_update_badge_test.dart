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

Map<String, Object?> _batchUpdate({
  int id = 7,
  int? updateAt,
}) {
  return <String, Object?>{
    'id': id,
    'ok': true,
    'name': 'Comic',
    'author': 'Author',
    'image': 'cover.webp',
    'description': '',
    'update_at': updateAt,
    'addtime': 100,
    'error': '',
  };
}

Map<String, Object?> _batchFailure(int id) => <String, Object?>{
      'id': id,
      'ok': false,
      'error': 'temporary failure',
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
        case 'bookshelf_update_batch':
          return _response([_batchUpdate(updateAt: 200)]);
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

  testWidgets('refresh resolves updates through one batch bridge request',
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
        case 'bookshelf_update_batch':
          return _response([_batchUpdate(updateAt: 200)]);
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

    requests.clear();
    await refreshLocalBookshelfUpdates(force: true);

    expect(localBookshelfItems.single.comic.updateAt, 200);
    expect(localBookshelfItems.single.hasUpdate, isTrue);
    final batchRequest = requests
        .where(
          (request) => request['method'] == 'bookshelf_update_batch',
        )
        .single;
    expect(
      jsonDecode(batchRequest['params'] as String),
      {
        'ids': [7],
      },
    );
    expect(
      requests.where((request) => request['method'] == 'album'),
      isEmpty,
    );
    expect(
      requests.where((request) => request['method'] == 'chapter'),
      isEmpty,
    );
    expect(
      requests.where(
        (request) =>
            request['method'] == 'save_property' &&
            '${request['params']}'.contains('startup_cache_album_'),
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('one batch request updates all shelf comics and keeps failures',
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
        case 'bookshelf_update_batch':
          final params =
              jsonDecode(request['params'] as String) as Map<String, dynamic>;
          final ids = (params['ids'] as List).cast<int>();
          return _response([
            for (final id in ids)
              if (id == 9)
                _batchFailure(id)
              else
                _batchUpdate(id: id, updateAt: id == 7 ? 200 : 300),
          ]);
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
    for (final id in [7, 8, 9]) {
      await toggleLocalBookshelf(
        ComicBasic(
          id: id,
          author: 'Author',
          description: '',
          name: 'Comic $id',
          image: 'cover-$id.webp',
          updateAt: 100,
        ),
      );
    }

    requests.clear();
    await refreshLocalBookshelfUpdates(force: true);

    final batches = requests.where(
      (request) => request['method'] == 'bookshelf_update_batch',
    );
    expect(batches, hasLength(1));
    final params = jsonDecode(batches.single['params'] as String);
    expect((params['ids'] as List).toSet(), {7, 8, 9});
    expect(
      localBookshelfItems
          .singleWhere((item) => item.comic.id == 7)
          .comic
          .updateAt,
      200,
    );
    expect(
      localBookshelfItems
          .singleWhere((item) => item.comic.id == 8)
          .comic
          .updateAt,
      300,
    );
    expect(
      localBookshelfItems
          .singleWhere((item) => item.comic.id == 9)
          .comic
          .updateAt,
      100,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual refresh keeps the loaded local shelf in memory',
      (tester) async {
    final properties = <String, String>{};
    var shelfStorageLoads = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (request['method']) {
        case 'load_property':
          final key = '${request['params']}';
          if (key == 'local_bookshelf_v1') shelfStorageLoads++;
          return _response(properties[key] ?? '');
        case 'save_property':
          final values =
              jsonDecode(request['params'] as String) as Map<String, dynamic>;
          properties[values['k'] as String] = values['v'] as String;
          return _response('');
        case 'bookshelf_update_batch':
          return _response([_batchUpdate(updateAt: 200)]);
        default:
          return _response('');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      resetLocalBookshelfMemory();
    });

    await initPagerViewMode();
    await initPagerCoverRate();
    await initPagerColumnCount();
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

    resetLocalBookshelfMemory();
    properties['local_bookshelf_updates_checked_at'] =
        DateTime.now().millisecondsSinceEpoch.toString();
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: BookshelfScreen(),
    ));
    await tester.pumpAndSettle();

    final loadsBeforeRefresh = shelfStorageLoads;
    await tester.tap(find.byKey(const ValueKey('bookshelf-options-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Refresh'), findsNothing);
    expect(find.text('Manage groups'), findsOneWidget);
    expect(find.text('Sort'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('bookshelf-folder-grid')),
      const Offset(0, 360),
    );
    await tester.pumpAndSettle();

    expect(shelfStorageLoads, loadsBeforeRefresh);
    expect(localBookshelfItems.single.comic.name, 'Comic');
    expect(tester.takeException(), isNull);
  });
}
