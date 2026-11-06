import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/async_semaphore.dart';

void main() {
  test('async semaphore never exceeds its concurrency limit', () async {
    final semaphore = AsyncSemaphore(4);
    var active = 0;
    var maximumActive = 0;

    await Future.wait(
      List.generate(16, (index) {
        return semaphore.run(() async {
          active++;
          if (active > maximumActive) maximumActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
          return index;
        });
      }),
    );

    expect(maximumActive, 4);
    expect(active, 0);
  });
}
