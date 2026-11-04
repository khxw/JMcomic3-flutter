import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/basic/local_bookshelf.dart';
import 'package:jmcomic3/configs/local_bookshelf_backup.dart';

const _channel = MethodChannel('methods');

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });

ComicBasic _comic(int id, String name) => ComicBasic.fromJson({
      'id': id,
      'author': 'author',
      'description': '',
      'name': name,
      'image': '$id.jpg',
      'category': {'id': '1', 'title': 'category'},
      'category_sub': {'id': '2', 'title': 'subcategory'},
      'update_at': 0,
      'addtime': 0,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bookshelf backup merges items, preserves groups and skips duplicates',
      () async {
    final properties = <String, String>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      switch (request['method']) {
        case 'load_property':
          return _response(properties[request['params']] ?? '');
        case 'save_property':
          final values = jsonDecode(request['params'] as String) as Map;
          properties[values['k'] as String] = values['v'] as String;
          return _response('');
        default:
          return _response('');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      resetLocalBookshelfMemory();
    });
    resetLocalBookshelfMemory();

    await toggleLocalBookshelf(_comic(1, 'existing'), group: 'Existing');
    final backup = OfflineBookshelfBackupData.parse(jsonEncode({
      'format': 'jmcomic3-offline-bookshelf',
      'version': 1,
      'groups': ['Imported', 'Shared'],
      'items': [
        LocalBookshelfItem(
          comic: _comic(1, 'existing'),
          addedAt: 10,
          group: 'Imported',
        ).toJson(),
        LocalBookshelfItem(
          comic: _comic(2, 'imported'),
          addedAt: 20,
          group: 'Shared',
        ).toJson(),
      ],
    }));
    final result = await importOfflineBookshelfBackup(backup);

    expect(result.added, 1);
    expect(result.skipped, 1);
    expect(result.groupsAdded, 2);
    expect(localBookshelfItems, hasLength(2));
    expect(localBookshelfGroupNames, containsAll(['Existing', 'Shared']));
    expect(
      localBookshelfItems.singleWhere((item) => item.comic.id == 1).group,
      'Existing',
    );
    expect(
      localBookshelfItems.singleWhere((item) => item.comic.id == 2).group,
      'Shared',
    );
  });

  test('bookshelf backup round trip keeps items and groups', () async {
    final properties = <String, String>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      switch (request['method']) {
        case 'load_property':
          return _response(properties[request['params']] ?? '');
        case 'save_property':
          final values = jsonDecode(request['params'] as String) as Map;
          properties[values['k'] as String] = values['v'] as String;
          return _response('');
        default:
          return _response('');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      resetLocalBookshelfMemory();
    });
    resetLocalBookshelfMemory();

    await toggleLocalBookshelf(_comic(7, 'saved'), group: 'Favorites');
    final exported = await encodeOfflineBookshelfBackup();
    final parsed = OfflineBookshelfBackupData.parse(exported);

    expect(parsed.items, hasLength(1));
    expect(parsed.items.single.comic.name, 'saved');
    expect(parsed.groups, contains('Favorites'));
    expect(jsonDecode(exported)['format'], 'jmcomic3-offline-bookshelf');
  });
}
