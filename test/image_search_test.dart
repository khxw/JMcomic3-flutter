import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/image_search_screen.dart';
import 'package:jmcomic3/screens/search_screen.dart';

const _channel = MethodChannel('methods');

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search page can recognize an image and open the best comic',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      requests.add(request);
      switch (request['method']) {
        case 'last_search_histories':
          return _response(<Object>[]);
        case 'categories':
          return _response({
            'categories': <Object>[],
            'blocks': <Object>[],
          });
        case 'image_search':
          final params =
              jsonDecode(request['params'] as String) as Map<String, dynamic>;
          expect(params['path'], 'C:\\tmp\\comic.jpg');
          return _response({
            'result_id': 'fixture',
            'status': 'complete',
            'partial': false,
            'elapsed_ms': 1200,
            'warnings': <Object>[],
            'hits': [
              {
                'source': 'jmcomic',
                'external_id': '1214196',
                'title': 'Fixture Comic',
                'title_alt': '',
                'language': 'zh',
                'page': 8,
                'similarity': 94.2,
                'url': 'https://example.test/photo/1214196',
                'thumbnail_url': '',
              },
              {
                'source': 'nhentai',
                'external_id': '99',
                'title': 'Another Fixture',
                'title_alt': '',
                'language': 'ja',
                'page': 3,
                'similarity': 86.0,
                'url': 'https://example.test/g/99',
                'thumbnail_url': '',
              },
            ],
          });
        case 'comic_search':
          return _response({
            'total': 0,
            'content': <Object>[],
          });
        default:
          return _response('');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
    });

    await initPagerViewMode();
    await initPagerControllerMode();
    await initPagerCoverRate();
    await initPagerColumnCount();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SearchScreen(
        imageSearchPageBuilder: (_) => ImageSearchScreen(
          pickGallery: () async => 'C:\\tmp\\comic.jpg',
          pickFiles: () async => 'C:\\tmp\\comic.jpg',
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('search-image-search')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('image-search-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('image-search-test-badge')),
      findsOneWidget,
    );
    expect(find.text('Test feature'), findsOneWidget);
    expect(find.byKey(const ValueKey('image-search-gallery')), findsOneWidget);
    expect(find.byKey(const ValueKey('image-search-files')), findsOneWidget);
    expect(
      requests.where((request) => request['method'] == 'image_search'),
      isEmpty,
    );

    await tester.tap(find.byKey(const ValueKey('image-search-gallery')));
    await tester.pumpAndSettle();

    expect(
      requests.where((request) => request['method'] == 'image_search'),
      hasLength(1),
    );
    expect(find.text('Fixture Comic'), findsOneWidget);
    expect(find.text('Another Fixture'), findsOneWidget);

    final firstCandidate =
        find.byKey(const ValueKey('image-search-candidate-0'));
    await tester.ensureVisible(firstCandidate);
    await tester.pumpAndSettle();
    await tester.tap(firstCandidate);
    await tester.pumpAndSettle();

    final comicSearch =
        requests.where((request) => request['method'] == 'comic_search').single;
    final params =
        jsonDecode(comicSearch['params'] as String) as Map<String, dynamic>;
    expect(params['search_query'], '1214196');
    expect(find.text('Image match: Fixture Comic'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('numeric search keeps results behind comic detail navigation',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (request['method']) {
        case 'last_search_histories':
          return _response(<Object>[]);
        case 'categories':
          return _response({
            'categories': <Object>[],
            'blocks': <Object>[],
          });
        case 'comic_search':
          return _response({
            'total': 1,
            'content': <Object>[],
            'redirect_aid': 1214196,
          });
        case 'album':
          return _response({
            'id': 1214196,
            'name': 'Fixture Comic',
            'author': ['Author'],
            'images': <Object>[],
            'description': '',
            'total_views': 0,
            'likes': 0,
            'series': <Object>[],
            'series_id': 0,
            'comment_total': 0,
            'tags': <Object>[],
            'works': <Object>[],
            'related_list': <Object>[],
            'liked': false,
            'is_favorite': false,
            'addtime': 100,
            'update_at': 200,
          });
        case 'find_view_log':
          return _response({
            'id': 1214196,
            'author': '',
            'description': '',
            'name': 'Fixture Comic',
            'last_view_time': 0,
            'last_view_chapter_id': 0,
            'last_view_page': 0,
          });
        case 'chapter':
          return _response({
            'id': 1214196,
            'series': <Object>[],
            'tags': '',
            'name': '',
            'images': <Object>[],
            'series_id': 1214196,
            'is_favorite': false,
            'liked': false,
            'addtime': 200,
          });
        case 'album_published_at':
          return _response('2025-09-12');
        case 'load_property':
          return _response('');
        default:
          return _response('');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
    });

    await initPagerViewMode();
    await initPagerControllerMode();
    await initPagerCoverRate();
    await initPagerColumnCount();
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SearchScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('compose-search-field')),
      '1214196',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    final back = find.byKey(const ValueKey('comic-detail-back'));
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(find.text('Search results'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('compose-search-field')),
    );
    expect(field.controller?.text, '1214196');
    expect(tester.takeException(), isNull);
  });

  testWidgets('image search retries JM using original titles and aliases',
      (tester) async {
    final queries = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      switch (request['method']) {
        case 'last_search_histories':
          return _response(<Object>[]);
        case 'categories':
          return _response({
            'categories': <Object>[],
            'blocks': <Object>[],
          });
        case 'image_search':
          return _response({
            'hits': [
              {
                'source': 'nhentai',
                'external_id': '99',
                'title': 'Different English Title',
                'title_alt': 'Japanese Alias',
                'aliases': ['Romanized Alias'],
                'works': ['Original Work'],
                'creators': ['Artist'],
                'language': 'en',
                'similarity': 91,
              },
            ],
          });
        case 'comic_search':
          final params =
              jsonDecode(request['params'] as String) as Map<String, dynamic>;
          queries.add(params['search_query'] as String);
          expect(params['record_search'], isFalse);
          return _response({
            'total': 0,
            'content': <Object>[],
          });
        case 'load_property':
          return _response('');
        default:
          return _response('');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await initPagerViewMode();
    await initPagerControllerMode();
    await initPagerCoverRate();
    await initPagerColumnCount();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SearchScreen(
        imageSearchPageBuilder: (_) => ImageSearchScreen(
          pickGallery: () async => 'C:\\tmp\\comic.jpg',
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('search-image-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('image-search-gallery')));
    await tester.pumpAndSettle();

    final candidate = find.byKey(const ValueKey('image-search-candidate-0'));
    await tester.ensureVisible(candidate);
    await tester.pumpAndSettle();
    await tester.tap(candidate);
    await tester.pumpAndSettle();

    expect(queries, contains('Original Work'));
    expect(queries, contains('Japanese Alias'));
    expect(queries, contains('Different English Title'));
    expect(find.text('Image match: Different English Title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image source shows feedback while the system picker opens',
      (tester) async {
    final galleryGate = Completer<String?>();
    var filePickerCalls = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ImageSearchScreen(
        pickGallery: () => galleryGate.future,
        pickFiles: () async {
          filePickerCalls++;
          return null;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('image-search-gallery')));
    await tester.pump();

    expect(find.text('Opening system photo picker...'), findsOneWidget);
    expect(find.byKey(const ValueKey('image-source-opening')), findsOneWidget);
    expect(find.byKey(const ValueKey('image-picker-handoff')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('image-search-files')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(filePickerCalls, 0);

    galleryGate.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('image search entities tolerate missing optional fields', () {
    final response = ImageSearchResponse.fromJson({
      'result_id': 'fixture',
      'hits': [
        {
          'source': 'jmcomic',
          'external_id': '42',
          'similarity': '88.5',
        },
        {
          'source': 'nhentai',
          'external_id': '99',
          'title': 'Different English Title [Chinese]',
          'title_alt': 'Japanese Alias',
          'aliases': ['Romanized Alias'],
          'works': ['Original Work'],
          'creators': ['Artist'],
          'similarity': 80,
        },
      ],
    });

    expect(response.hits.first.searchQuery, '42');
    expect(response.hits.first.similarity, 88.5);
    expect(response.hits.first.displayTitle, 'JMComic #42');
    expect(response.hits[1].searchQueries.first, 'Original Work');
    expect(
      response.hits[1].searchQueries,
      contains('Japanese Alias'),
    );
    expect(
      response.hits[1].searchQueries,
      contains('Different English Title [Chinese]'),
    );
  });
}
