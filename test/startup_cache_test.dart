import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';

const _channel = MethodChannel('methods');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('home feeds use the persisted startup cache without a network call',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final categoriesPayload = jsonEncode({
      'categories': [
        {
          'id': 1,
          'name': 'Alpha',
          'slug': 'alpha',
          'total_albums': 1,
        }
      ],
      'blocks': [
        {
          'title': 'Home',
          'content': ['alpha'],
        }
      ],
    });
    final comicsPayload = jsonEncode({
      'search_query': '',
      'total': 1,
      'content': [
        {
          'id': 1,
          'author': '',
          'description': '',
          'name': 'Cached comic',
          'image': '',
        }
      ],
    });
    final albumPayload = jsonEncode({
      'id': 1,
      'name': 'Cached album',
      'author': ['Writer'],
      'images': <String>[],
      'description': 'Cached details',
      'total_views': 10,
      'likes': 2,
      'series': <Object>[],
      'series_id': 1,
      'comment_total': 0,
      'tags': <String>[],
      'works': <String>[],
      'related_list': <Object>[],
      'liked': false,
      'is_favorite': false,
    });
    final comicsKey = 'startup_cache_comics_v1_'
        '${base64Url.encode(utf8.encode('alpha|mr|1')).replaceAll('=', '')}';
    final albumKey = 'startup_cache_album_v1_'
        '${base64Url.encode(utf8.encode('1|false')).replaceAll('=', '')}';
    final properties = <String, String>{
      'startup_cache_categories_v1': _persisted(now, categoriesPayload),
      comicsKey: _persisted(now, comicsPayload),
      albumKey: _persisted(now, albumPayload),
    };
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final method = request['method'] as String;
      final params = request['params']?.toString() ?? '';
      calls.add(method);
      if (method == 'load_property') {
        return _response(properties[params] ?? '');
      }
      return _response('');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    final categories = await methods.categories();
    final comics = await methods.comics('alpha', sortByNew, 1);
    final album = await methods.album(1);

    expect(categories.categories.single.name, 'Alpha');
    expect(comics.content.single.name, 'Cached comic');
    expect(album.name, 'Cached album');
    expect(calls, isNot(contains('categories')));
    expect(calls, isNot(contains('comics')));
    expect(calls, isNot(contains('album')));
  });
}

String _persisted(int savedAt, String value) => jsonEncode({
      'saved_at': savedAt,
      'value': value,
    });

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });
