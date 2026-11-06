import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/reader_preload.dart';

void main() {
  test('reader preload configuration accepts supported distances', () {
    expect(parseReaderPreloadPages('0'), 0);
    expect(parseReaderPreloadPages(' 2 '), 2);
    expect(parseReaderPreloadPages('6'), 6);
    expect(parseReaderPreloadPages('3'), 2);
    expect(parseReaderPreloadPages('invalid'), 2);
  });

  test('reader preload direction defaults to both ways', () {
    expect(parseReaderPreloadForwardOnly(''), isFalse);
    expect(parseReaderPreloadForwardOnly('false'), isFalse);
    expect(parseReaderPreloadForwardOnly('true'), isTrue);
    expect(parseReaderPreloadForwardOnly('1'), isTrue);
    expect(parseReaderPreloadForwardOnly('forward'), isTrue);
  });

  test('reader preload warms pages before and after the current page', () {
    expect(
      readerPreloadIndices(
        current: 5,
        total: 20,
        pages: 2,
        paired: false,
      ),
      [6, 4, 7, 3],
    );
    expect(
      readerPreloadIndices(
        current: 4,
        total: 20,
        pages: 2,
        paired: true,
      ),
      [6, 2, 8, 0],
    );
    expect(
      readerPreloadIndices(
        current: 0,
        total: 3,
        pages: 4,
        paired: false,
      ),
      [1, 2],
    );
    expect(
      readerPreloadIndices(
        current: 1,
        total: 3,
        pages: 0,
        paired: false,
      ),
      isEmpty,
    );
  });

  test('reader preload can warm forward pages only', () {
    expect(
      readerPreloadIndices(
        current: 5,
        total: 20,
        pages: 2,
        paired: false,
        forwardOnly: true,
      ),
      [6, 7],
    );
    expect(
      readerPreloadIndices(
        current: 4,
        total: 20,
        pages: 2,
        paired: true,
        forwardOnly: true,
      ),
      [6, 8],
    );
  });
}
