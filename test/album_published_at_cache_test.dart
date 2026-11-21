import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';

const _channel = MethodChannel('methods');

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('publish-date lookups are coalesced and persisted', () async {
    final properties = <String, String>{};
    final gate = Completer<void>();
    var networkCalls = 0;
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
        case 'album_published_at':
          networkCalls++;
          await gate.future;
          return _response('2025-09-12');
        default:
          return _response('');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      methods.resetAlbumPublishedDateCacheForTest();
    });

    methods.resetAlbumPublishedDateCacheForTest();
    final first = methods.albumPublishedAt(42, 'Comic');
    final second = methods.albumPublishedAt(42, 'Comic');
    await Future<void>.delayed(Duration.zero);
    gate.complete();

    expect(await Future.wait([first, second]), ['2025-09-12', '2025-09-12']);
    expect(networkCalls, 1);

    methods.resetAlbumPublishedDateCacheForTest();
    expect(await methods.albumPublishedAt(42, 'Comic'), '2025-09-12');
    expect(networkCalls, 1);
  });

  test('empty publish-date lookups are negatively cached', () async {
    final properties = <String, String>{};
    var networkCalls = 0;
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
        case 'album_published_at':
          networkCalls++;
          return _response('');
        default:
          return _response('');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      methods.resetAlbumPublishedDateCacheForTest();
    });

    methods.resetAlbumPublishedDateCacheForTest();
    expect(await methods.albumPublishedAt(43, 'Unknown'), '');
    expect(await methods.albumPublishedAt(43, 'Unknown'), '');
    expect(networkCalls, 1);
  });
}
