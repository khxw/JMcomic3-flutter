import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/http_client.dart';

void main() {
  test('update downloader streams to disk and reports progress', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final payload = List<int>.generate(128 * 1024, (index) => index % 251);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.binary
        ..headers.contentLength = payload.length
        ..add(payload);
      await request.response.close();
    });

    final directory = await Directory.systemTemp.createTemp('jm3-update-');
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/update.apk');
    final progress = <double?>[];

    await AppHttpClient.downloadFile(
      'http://${server.address.host}:${server.port}/update.apk',
      destination,
      onProgress: progress.add,
    );

    expect(await destination.readAsBytes(), payload);
    expect(await File('${destination.path}.part').exists(), isFalse);
    expect(progress, isNotEmpty);
    expect(progress.last, 1);
    expect(progress.whereType<double>().every((value) => value <= 1), isTrue);
  });

  test('paused update keeps partial data and resumes with Range', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final payload = List<int>.generate(256 * 1024, (index) => index % 239);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      var start = 0;
      if (range != null) {
        final match = RegExp(r'^bytes=(\d+)-$').firstMatch(range);
        start = int.tryParse(match?.group(1) ?? '') ?? 0;
      }
      if (start > 0) {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${payload.length - 1}/${payload.length}',
          )
          ..headers.contentType = ContentType.binary
          ..headers.contentLength = payload.length - start;
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary
          ..headers.contentLength = payload.length;
      }
      try {
        for (var offset = start; offset < payload.length; offset += 1024) {
          final end =
              offset + 1024 < payload.length ? offset + 1024 : payload.length;
          request.response.add(payload.sublist(offset, end));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        await request.response.close();
      } catch (_) {
        // The client intentionally closes the first response when paused.
      }
    });

    final directory = await Directory.systemTemp.createTemp('jm3-resume-');
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/update.apk');
    final partial = File('${destination.path}.part');
    final control = DownloadControl();
    var pauseRequested = false;

    await expectLater(
      AppHttpClient.downloadFile(
        'http://${server.address.host}:${server.port}/update.apk',
        destination,
        control: control,
        onProgress: (value) {
          if (!pauseRequested && value != null && value > 0 && value < 1) {
            pauseRequested = true;
            control.pause();
          }
        },
      ),
      throwsA(isA<DownloadPausedException>()),
    );

    expect(await partial.exists(), isTrue);
    final partialBytes = await partial.length();
    expect(partialBytes, greaterThan(0));
    expect(partialBytes, lessThan(payload.length));

    final resumedProgress = <double?>[];
    await AppHttpClient.downloadFile(
      'http://${server.address.host}:${server.port}/update.apk',
      destination,
      resume: true,
      onProgress: resumedProgress.add,
    );

    expect(await destination.readAsBytes(), payload);
    expect(await partial.exists(), isFalse);
    expect(resumedProgress.last, 1);
  });
}
