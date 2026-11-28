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
        pickImageFile: () async => 'C:\\tmp\\comic.jpg',
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('search-image-search')));
    await tester.pumpAndSettle();

    expect(
      requests.where((request) => request['method'] == 'image_search'),
      hasLength(1),
    );
    expect(find.byKey(const ValueKey('image-search-results')), findsOneWidget);
    expect(find.text('Fixture Comic'), findsOneWidget);
    expect(find.text('Another Fixture'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('image-search-candidate-0')),
    );
    await tester.pumpAndSettle();

    final comicSearch =
        requests.where((request) => request['method'] == 'comic_search').single;
    final params =
        jsonDecode(comicSearch['params'] as String) as Map<String, dynamic>;
    expect(params['search_query'], '1214196');
    expect(find.text('Image match: Fixture Comic'), findsOneWidget);
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
      ],
    });

    expect(response.hits.single.searchQuery, '42');
    expect(response.hits.single.similarity, 88.5);
    expect(response.hits.single.displayTitle, 'JMComic #42');
  });
}
