import 'dart:convert';

import 'package:event/event.dart';
import 'package:flutter/foundation.dart';
import 'package:jmcomic3/basic/methods.dart';

import 'async_semaphore.dart';

const _storageKey = "local_bookshelf_v1";
const _groupsStorageKey = "local_bookshelf_groups_v1";
const _updatesCheckedAtKey = "local_bookshelf_updates_checked_at";
const _updatesRefreshInterval = Duration(minutes: 10);

final Event localBookshelfEvent = Event();
final List<LocalBookshelfItem> localBookshelfItems = [];
final List<String> localBookshelfGroups = [];

bool _loaded = false;
Future<void>? _loading;

class LocalBookshelfItem {
  final ComicBasic comic;
  final int addedAt;
  final String group;
  final int? lastSeenUpdateAt;

  const LocalBookshelfItem({
    required this.comic,
    required this.addedAt,
    required this.group,
    this.lastSeenUpdateAt,
  });

  factory LocalBookshelfItem.fromJson(Map<String, dynamic> json) {
    final comicJson = json['comic'];
    final comic = ComicBasic.fromJson(
      comicJson is Map
          ? Map<String, dynamic>.from(comicJson)
          : <String, dynamic>{},
    );
    return LocalBookshelfItem(
      comic: comic,
      addedAt: _toInt(json['added_at']),
      group: "${json['group'] ?? ''}".trim(),
      lastSeenUpdateAt:
          _toNullableInt(json['last_seen_update_at']) ?? comic.updateAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'comic': comic.toJson(),
        'added_at': addedAt,
        'group': group,
        'last_seen_update_at': lastSeenUpdateAt,
      };

  bool get hasUpdate {
    final updatedAt = comic.updateAt;
    final seenAt = lastSeenUpdateAt ?? updatedAt;
    return updatedAt != null &&
        updatedAt > 0 &&
        seenAt != null &&
        updatedAt > seenAt;
  }

  LocalBookshelfItem copyWith({
    String? group,
    ComicBasic? comic,
    int? lastSeenUpdateAt,
  }) =>
      LocalBookshelfItem(
        comic: comic ?? this.comic,
        addedAt: addedAt,
        group: group ?? this.group,
        lastSeenUpdateAt: lastSeenUpdateAt ?? this.lastSeenUpdateAt,
      );

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse("$value") ?? 0;
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse("$value");
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

Future<void> saveLocalBookshelf() => _saveStorage();

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

int localBookshelfUpdateCount(String? group) {
  return localBookshelfItems
      .where(
        (item) =>
            (group == null || _sameGroup(item.group, group)) && item.hasUpdate,
      )
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
      lastSeenUpdateAt: comic.updateAt,
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

Future<void> markLocalBookshelfItemSeen(int comicId) async {
  await loadLocalBookshelf();
  final index =
      localBookshelfItems.indexWhere((item) => item.comic.id == comicId);
  if (index < 0) return;
  final item = localBookshelfItems[index];
  final seenAt = item.comic.updateAt;
  if (seenAt == null || item.lastSeenUpdateAt == seenAt) return;
  localBookshelfItems[index] = item.copyWith(lastSeenUpdateAt: seenAt);
  await _saveStorage();
}

Future<int> refreshLocalBookshelfUpdates({bool force = false}) async {
  await loadLocalBookshelf();
  final now = DateTime.now();
  if (!force) {
    final raw = await methods.loadProperty(_updatesCheckedAtKey);
    final lastCheckedMs = int.tryParse(raw) ?? 0;
    if (lastCheckedMs > 0 &&
        now.millisecondsSinceEpoch - lastCheckedMs <
            _updatesRefreshInterval.inMilliseconds) {
      return 0;
    }
  }

  final snapshot = List<LocalBookshelfItem>.of(localBookshelfItems);
  final semaphore = AsyncSemaphore(4);
  final refreshed = await Future.wait(
    snapshot.map(
      (item) => semaphore.run<LocalBookshelfItem?>(() async {
        try {
          final album = await methods.album(
            item.comic.id,
            ignoreViewLog: true,
            forceRefresh: true,
          );
          var resolvedUpdateAt = album.updateAt;
          if (resolvedUpdateAt == null || resolvedUpdateAt <= 0) {
            try {
              final chapter =
                  await methods.chapter(album.latestUpdateChapterId);
              resolvedUpdateAt = chapter.addtime;
            } catch (_) {
              // Preserve the last known timestamp when the chapter lookup
              // fails instead of replacing it with null.
            }
          }
          final previousUpdateAt = item.comic.updateAt;
          final updateAt = resolvedUpdateAt != null && resolvedUpdateAt > 0
              ? previousUpdateAt != null && previousUpdateAt > resolvedUpdateAt
                  ? previousUpdateAt
                  : resolvedUpdateAt
              : previousUpdateAt;
          final image =
              album.images.isEmpty ? item.comic.image : album.images.first;
          final comic = ComicBasic(
            id: album.id,
            author: album.author.join(', '),
            description: album.description,
            name: album.name,
            image: image,
            updateAt: updateAt,
            addtime: album.addtime,
          );
          final lastSeen =
              item.lastSeenUpdateAt ?? previousUpdateAt ?? updateAt;
          return item.copyWith(
            comic: comic,
            lastSeenUpdateAt: lastSeen,
          );
        } catch (_) {
          return null;
        }
      }),
    ),
  );

  var changed = false;
  for (final updated in refreshed.whereType<LocalBookshelfItem>()) {
    final index = localBookshelfItems.indexWhere(
      (item) => item.comic.id == updated.comic.id,
    );
    if (index < 0) continue;
    final previous = localBookshelfItems[index];
    if (previous.comic.updateAt != updated.comic.updateAt ||
        previous.comic.name != updated.comic.name ||
        previous.comic.author != updated.comic.author ||
        previous.comic.description != updated.comic.description ||
        previous.comic.image != updated.comic.image) {
      localBookshelfItems[index] = updated;
      changed = true;
    }
  }
  if (changed) {
    await _saveStorage();
  }
  await methods.saveProperty(
    _updatesCheckedAtKey,
    now.millisecondsSinceEpoch.toString(),
  );
  return localBookshelfUpdateCount(null);
}

@visibleForTesting
void resetLocalBookshelfMemory() {
  localBookshelfItems.clear();
  localBookshelfGroups.clear();
  _loaded = false;
  _loading = null;
  localBookshelfEvent.broadcast();
}
