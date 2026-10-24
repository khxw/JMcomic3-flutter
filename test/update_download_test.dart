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
}
