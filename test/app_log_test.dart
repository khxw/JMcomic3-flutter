import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/app_log.dart';

void main() {
  setUp(AppLog.clear);

  test('runtime log redacts credentials and tokens', () {
    AppLog.add(
      'password=secret cookie=AVS123 token: abc '
      'Authorization=BearerValue',
      level: AppLogLevel.error,
    );

    final text = AppLog.exportText();
    expect(text, contains('password=<redacted>'));
    expect(text, contains('cookie=<redacted>'));
    expect(text, contains('token: <redacted>'));
    expect(text, isNot(contains('secret')));
    expect(text, isNot(contains('AVS123')));
    expect(text, isNot(contains('abc')));
  });

  test('runtime log keeps only the newest entries', () {
    for (var index = 0; index < AppLog.maxEntries + 8; index++) {
      AppLog.add('entry-$index');
    }

    expect(AppLog.entries, hasLength(AppLog.maxEntries));
    expect(AppLog.entries.first.message, 'entry-8');
    expect(
      AppLog.entries.last.message,
      'entry-${AppLog.maxEntries + 7}',
    );
  });
}
