import 'dart:convert';

import 'package:event/event.dart';
import 'package:flutter/foundation.dart';
import 'package:jmcomic3/basic/methods.dart';

const _storageKey = "local_bookshelf_v1";
const _groupsStorageKey = "local_bookshelf_groups_v1";

final Event localBookshelfEvent = Event();
final List<LocalBookshelfItem> localBookshelfItems = [];
final List<String> localBookshelfGroups = [];

bool _loaded = false;
Future<void>? _loading;

class LocalBookshelfItem {
  final ComicBasic comic;
  final int addedAt;
  final String group;

  const LocalBookshelfItem({
    required this.comic,
    required this.addedAt,
    required this.group,
  });

  factory LocalBookshelfItem.fromJson(Map<String, dynamic> json) {
    final comicJson = json['comic'];
    return LocalBookshelfItem(
      comic: ComicBasic.fromJson(
        comicJson is Map
            ? Map<String, dynamic>.from(comicJson)
            : <String, dynamic>{},
      ),
      addedAt: _toInt(json['added_at']),
      group: "${json['group'] ?? ''}".trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'comic': comic.toJson(),
        'added_at': addedAt,
        'group': group,
      };

  LocalBookshelfItem copyWith({String? group}) => LocalBookshelfItem(
        comic: comic,
        addedAt: addedAt,
        group: group ?? this.group,
      );

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse("$value") ?? 0;
  }
}

Future<void> loadLocalBookshelf({bool force = false}) {
  if (_loaded && !force) return Future<void>.value();
  if (_loading != null) return _loading!;
  _loading = _readStorage().whenComplete(() => _loading = null);
  return _loading!;
}

Future<void> _readStorage() async {
  localBookshelfItems.clear();
  localBookshelfGroups.clear();
  try {
    final raw = await methods.loadProperty(_storageKey);
    if (raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final entry in decoded.whereType<Map>()) {
          final item = LocalBookshelfItem.fromJson(
            Map<String, dynamic>.from(entry),
          );
          if (item.comic.id > 0) {
            localBookshelfItems.add(item);
          }
        }
      }
    }
  } catch (_) {
    localBookshelfItems.clear();
  }
  try {
    final rawGroups = await methods.loadProperty(_groupsStorageKey);
    if (rawGroups.trim().isNotEmpty) {
      final decodedGroups = jsonDecode(rawGroups);
      if (decodedGroups is List) {
        for (final value in decodedGroups) {
          _rememberGroup("$value");
        }
      }
    }
  } catch (_) {
    localBookshelfGroups.clear();
  }
  for (final item in localBookshelfItems) {
    _rememberGroup(item.group);
  }
  _loaded = true;
  localBookshelfEvent.broadcast();
}

Future<void> _saveStorage() async {
  final itemsValue = jsonEncode(
    localBookshelfItems.map((item) => item.toJson()).toList(growable: false),
  );
  final groupsValue = jsonEncode(localBookshelfGroups);
  await methods.saveProperty(_storageKey, itemsValue);
  await methods.saveProperty(_groupsStorageKey, groupsValue);
  localBookshelfEvent.broadcast();
}

String _normalizedGroup(String value) => value.trim();

bool _sameGroup(String left, String right) =>
    left.trim().toLowerCase() == right.trim().toLowerCase();

void _rememberGroup(String value) {
  final normalized = _normalizedGroup(value);
  if (normalized.isEmpty) return;
  if (localBookshelfGroups.any((group) => _sameGroup(group, normalized))) {
    return;
  }
  localBookshelfGroups.add(normalized);
}

List<String> get localBookshelfGroupNames {
  final names = List<String>.of(localBookshelfGroups);
  names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return names;
}

int localBookshelfGroupCount(String group) {
  return localBookshelfItems
      .where((item) => _sameGroup(item.group, group))
      .length;
}

bool localBookshelfContains(int comicId) {
  return localBookshelfItems.any((item) => item.comic.id == comicId);
}

Future<bool> toggleLocalBookshelf(
  ComicBasic comic, {
  String group = "",
}) async {
  await loadLocalBookshelf();
  final index = localBookshelfItems.indexWhere(
    (item) => item.comic.id == comic.id,
  );
  if (index >= 0) {
    localBookshelfItems.removeAt(index);
    await _saveStorage();
    return false;
  }

  localBookshelfItems.insert(
    0,
    LocalBookshelfItem(
      comic: comic,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      group: group.trim(),
    ),
  );
  _rememberGroup(group);
  await _saveStorage();
  return true;
}

Future<void> removeLocalBookshelfItem(int comicId) async {
  await loadLocalBookshelf();
  localBookshelfItems.removeWhere((item) => item.comic.id == comicId);
  await _saveStorage();
}

Future<bool> createLocalBookshelfGroup(String name) async {
  await loadLocalBookshelf();
  final normalized = _normalizedGroup(name);
  if (normalized.isEmpty ||
      localBookshelfGroups.any((group) => _sameGroup(group, normalized))) {
    return false;
  }
  localBookshelfGroups.add(normalized);
  await _saveStorage();
  return true;
}

Future<bool> renameLocalBookshelfGroup(String oldName, String newName) async {
  await loadLocalBookshelf();
  final from = _normalizedGroup(oldName);
  final to = _normalizedGroup(newName);
  if (from.isEmpty || to.isEmpty) return false;
  if (from == to) return true;
  final sourceIndex =
      localBookshelfGroups.indexWhere((group) => _sameGroup(group, from));
  if (sourceIndex < 0) return false;
  final hasConflict = localBookshelfGroups
      .asMap()
      .entries
      .any((entry) => entry.key != sourceIndex && _sameGroup(entry.value, to));
  if (hasConflict) return false;
  localBookshelfGroups[sourceIndex] = to;
  for (var index = 0; index < localBookshelfItems.length; index++) {
    final item = localBookshelfItems[index];
    if (_sameGroup(item.group, from)) {
      localBookshelfItems[index] = item.copyWith(group: to);
    }
  }
  await _saveStorage();
  return true;
}

Future<void> deleteLocalBookshelfGroup(String name) async {
  await loadLocalBookshelf();
  final normalized = _normalizedGroup(name);
  if (normalized.isEmpty) return;
  localBookshelfGroups.removeWhere((group) => _sameGroup(group, normalized));
  for (var index = 0; index < localBookshelfItems.length; index++) {
    final item = localBookshelfItems[index];
    if (_sameGroup(item.group, normalized)) {
      localBookshelfItems[index] = item.copyWith(group: "");
    }
  }
  await _saveStorage();
}

Future<bool> moveLocalBookshelfItem(int comicId, String group) async {
  await loadLocalBookshelf();
  final index =
      localBookshelfItems.indexWhere((item) => item.comic.id == comicId);
  if (index < 0) return false;
  final normalized = _normalizedGroup(group);
  localBookshelfItems[index] =
      localBookshelfItems[index].copyWith(group: normalized);
  _rememberGroup(normalized);
  await _saveStorage();
  return true;
}

@visibleForTesting
void resetLocalBookshelfMemory() {
  localBookshelfItems.clear();
  localBookshelfGroups.clear();
  _loaded = false;
  _loading = null;
  localBookshelfEvent.broadcast();
}
