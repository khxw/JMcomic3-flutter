import 'dart:async';
import 'dart:collection';

enum AppLogLevel { info, warning, error }

class AppLogEntry {
  AppLogEntry({
    required this.time,
    required this.level,
    required this.message,
  });

  final DateTime time;
  final AppLogLevel level;
  final String message;

  String get formattedTime {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  String get formatted =>
      '[$formattedTime] ${level.name.toUpperCase()} $message';
}

class AppLog {
  AppLog._();

  static const int maxEntries = 1500;
  static final List<AppLogEntry> _entries = [];
  static final StreamController<List<AppLogEntry>> _changes =
      StreamController<List<AppLogEntry>>.broadcast();

  static final RegExp _secretPattern = RegExp(
    r'\b(password|passwd|pwd|cookie|token|authorization|secret|access[_-]?key|cd[_-]?key)\b(\s*[:=]\s*)([^\s,;&]+)',
    caseSensitive: false,
  );
  static final RegExp _bearerPattern =
      RegExp(r'\bbearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false);

  static UnmodifiableListView<AppLogEntry> get entries =>
      UnmodifiableListView(_entries);

  static Stream<List<AppLogEntry>> get changes => _changes.stream;

  static void add(
    Object? message, {
    AppLogLevel level = AppLogLevel.info,
  }) {
    final raw = message?.toString().trim() ?? '';
    if (raw.isEmpty) return;
    _entries.add(
      AppLogEntry(
        time: DateTime.now(),
        level: level,
        message: _redact(raw),
      ),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    _changes.add(UnmodifiableListView(List<AppLogEntry>.from(_entries)));
  }

  static void clear() {
    _entries.clear();
    _changes.add(const []);
  }

  static String exportText() {
    return _entries.map((entry) => entry.formatted).join('\n');
  }

  static String _redact(String input) {
    return input
        .replaceAllMapped(
          _secretPattern,
          (match) => '${match.group(1)}${match.group(2)}<redacted>',
        )
        .replaceAll(_bearerPattern, 'Bearer <redacted>');
  }
}
