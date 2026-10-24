import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/network_ping.dart';

void main() {
  test('ping display uses the best warm sample', () async {
    final values = [1280, 340];
    final result = await measureHostPing(() async => values.removeAt(0));
    expect(result.coldMilliseconds, 1280);
    expect(result.bestMilliseconds, 340);
    expect(result.samples, 2);
  });

  test('ping display keeps the cold sample when warm-up fails', () async {
    var calls = 0;
    final result = await measureHostPing(() async {
      calls++;
      if (calls == 1) return 820;
      throw StateError('warming failed');
    });
    expect(result.bestMilliseconds, 820);
    expect(result.samples, 1);
  });

  test('ping duration switches from milliseconds to seconds', () {
    expect(formatPingDuration(199), '199 ms');
    expect(formatPingDuration(999), '999 ms');
    expect(formatPingDuration(1234), '1.2 s');
    expect(formatPingDuration(12340), '12 s');
  });

  test('invalid ping values are rejected', () async {
    expect(
      () => measureHostPing(() async => 0),
      throwsStateError,
    );
  });
}
