import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/github_download_mirrors.dart';
import 'package:jmcomic3/configs/super_resolution_models.dart';

Map<String, Object> _model({String? sha}) => {
      'id': 'realcugan-test-2x',
      'version': '1.0.0',
      'name': 'Real-CUGAN 2x',
      'description': 'Test model',
      'scale': 2,
      'model_format': superResolutionModelFormatRealCugan,
      'input_name': 'in0',
      'output_name': 'out0',
      'prepadding': 18,
      'download_url':
          'https://github.com/khxw/JMcomic3-flutter/releases/download/model/model.zip',
      'download_urls': [
        'https://gh-proxy.com/https://github.com/khxw/JMcomic3-flutter/releases/download/model/model.zip',
      ],
      'sha256': sha ?? List.filled(64, 'a').join(),
      'archive_bytes': 1024,
      'extracted_bytes': 4096,
      'license_name': 'MIT',
      'license_url': 'https://example.com/license',
    };

Uint8List _buildTestArchive() {
  final archive = Archive();
  for (final file in {
    superResolutionParamFileName: utf8.encode('param'),
    superResolutionWeightsFileName: utf8.encode('weights'),
    'LICENSE.txt': utf8.encode('MIT'),
  }.entries) {
    archive.addFile(
      ArchiveFile(file.key, file.value.length, file.value),
    );
  }
  final bytes = ZipEncoder().encode(archive);
  return Uint8List.fromList(bytes);
}

SuperResolutionModel _downloadModel({
  required List<String> urls,
  required int archiveBytes,
  String? sha256Value,
  int extractedBytes = 4096,
}) {
  return SuperResolutionModel(
    id: 'realcugan-test',
    version: '1.0.0',
    name: 'Real-CUGAN test',
    description: 'Test model',
    scale: 2,
    modelFormat: superResolutionModelFormatRealCugan,
    inputName: 'in0',
    outputName: 'out0',
    prepadding: 18,
    downloadUrls: urls,
    sha256: sha256Value ?? List.filled(64, 'a').join(),
    archiveBytes: archiveBytes,
    extractedBytes: extractedBytes,
    licenseName: 'MIT',
    licenseUrl: 'https://example.com/license',
  );
}

void main() {
  test('super-resolution manifest validates and deduplicates models', () {
    final models = parseSuperResolutionManifest(jsonEncode({
      'schema': 2,
      'models': [_model(), _model()],
    }));

    expect(models, hasLength(1));
    expect(models.single.id, 'realcugan-test-2x');
    expect(models.single.scale, 2);
    expect(models.single.downloadUrls, hasLength(2));
  });

  test('super-resolution manifest rejects invalid checksums', () {
    expect(
      () => parseSuperResolutionManifest(jsonEncode({
        'schema': 2,
        'models': [_model(sha: 'invalid')],
      })),
      throwsFormatException,
    );
  });

  test('finds the newest complete super-resolution installation', () async {
    final home = await Directory.systemTemp.createTemp('jm-super-resolution-');
    addTearDown(() => home.delete(recursive: true));
    final older = Directory(
      '${home.path}${Platform.pathSeparator}super_resolution_models'
      '${Platform.pathSeparator}waifu2x${Platform.pathSeparator}20250914',
    );
    final newer = Directory(
      '${home.path}${Platform.pathSeparator}super_resolution_models'
      '${Platform.pathSeparator}waifu2x${Platform.pathSeparator}20250915',
    );
    final incomplete = Directory(
      '${home.path}${Platform.pathSeparator}super_resolution_models'
      '${Platform.pathSeparator}broken${Platform.pathSeparator}1',
    );
    for (final directory in [older, newer, incomplete]) {
      await directory.create(recursive: true);
      await File(
        '${directory.path}${Platform.pathSeparator}$superResolutionParamFileName',
      ).writeAsString('param');
    }
    for (final directory in [older, newer]) {
      await File(
        '${directory.path}${Platform.pathSeparator}$superResolutionWeightsFileName',
      ).writeAsString('weights');
      await File(
        '${directory.path}${Platform.pathSeparator}install.json',
      ).writeAsString(jsonEncode({
        'id': 'waifu2x',
        'version': directory.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last,
        'model_format': superResolutionModelFormatRealCugan,
        'input_name': 'in0',
        'output_name': 'out0',
        'prepadding': 18,
        'installed_at': directory == newer
            ? DateTime.now().millisecondsSinceEpoch
            : DateTime.now()
                .subtract(const Duration(days: 1))
                .millisecondsSinceEpoch,
      }));
    }

    final installed = await findInstalledSuperResolutionModel(home.path);
    expect(installed?.version, '20250915');
    expect(installed?.paramFile.existsSync(), isTrue);
    expect(installed?.weightsFile.existsSync(), isTrue);
  });

  test('legacy Waifu2x installations are not selected', () async {
    final home = await Directory.systemTemp.createTemp('jm-legacy-model-');
    addTearDown(() => home.delete(recursive: true));
    final directory = Directory(
      '${home.path}${Platform.pathSeparator}super_resolution_models'
      '${Platform.pathSeparator}waifu2x-cunet-2x'
      '${Platform.pathSeparator}20250915',
    );
    await directory.create(recursive: true);
    await File(
      '${directory.path}${Platform.pathSeparator}$superResolutionParamFileName',
    ).writeAsString('param');
    await File(
      '${directory.path}${Platform.pathSeparator}$superResolutionWeightsFileName',
    ).writeAsString('weights');
    await File(
      '${directory.path}${Platform.pathSeparator}install.json',
    ).writeAsString(jsonEncode({
      'id': 'waifu2x-cunet-2x',
      'version': '20250915',
      'installed_at': DateTime.now().millisecondsSinceEpoch,
    }));

    expect(await findInstalledSuperResolutionModel(home.path), isNull);
  });

  test('published manifest matches the checked-in model package', () async {
    final manifestFile = File(
      'models${Platform.pathSeparator}super_resolution'
      '${Platform.pathSeparator}manifest.json',
    );
    final models = parseSuperResolutionManifest(
      await manifestFile.readAsString(),
    );
    expect(models, isNotEmpty);

    final model = models.first;
    final archiveName = Uri.parse(model.downloadUrls.first).pathSegments.last;
    final archiveFile = File(
      'models${Platform.pathSeparator}super_resolution'
      '${Platform.pathSeparator}packages'
      '${Platform.pathSeparator}$archiveName',
    );
    expect(await archiveFile.length(), model.archiveBytes);
    expect(
      '${await sha256.bind(archiveFile.openRead()).first}',
      model.sha256,
    );

    final archive = ZipDecoder().decodeBytes(
      await archiveFile.readAsBytes(),
      verify: true,
    );
    expect(
      archive.files.map((entry) => entry.name),
      containsAll([
        superResolutionParamFileName,
        superResolutionWeightsFileName,
        'LICENSE.txt',
      ]),
    );
  });

  test('model downloads use the same mirrors as software updates', () {
    const official =
        'https://raw.githubusercontent.com/khxw/JMcomic3-flutter/main/model.zip';
    final candidates = githubDownloadCandidates([official]);

    expect(candidates.take(3), [
      'https://gh-proxy.org/$official',
      'https://ghfast.top/$official',
      'https://gh-proxy.com/$official',
    ]);
    expect(candidates.last, official);
  });

  test('stalled model download times out instead of hanging', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    Socket? accepted;
    final subscription = server.listen((socket) {
      accepted = socket;
      socket.write(
        'HTTP/1.1 200 OK\r\n'
        'Content-Length: 100\r\n'
        'Content-Type: application/zip\r\n'
        '\r\n'
        'x',
      );
      socket.flush();
    });
    addTearDown(() async {
      accepted?.destroy();
      await subscription.cancel();
      await server.close();
    });

    final directory = await Directory.systemTemp.createTemp('jm-model-stall-');
    addTearDown(() => directory.delete(recursive: true));
    final archive = File(
      '${directory.path}${Platform.pathSeparator}model.zip.part',
    );
    final model = _downloadModel(
      urls: ['http://${server.address.address}:${server.port}/model.zip'],
      archiveBytes: 100,
    );

    await expectLater(
      downloadSuperResolutionArchiveForTest(
        uri: Uri.parse(model.downloadUrls.single),
        archiveFile: archive,
        model: model,
        stallTimeout: const Duration(milliseconds: 200),
      ).timeout(const Duration(seconds: 2)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('model installation skips a slow mirror and uses the next one',
      () async {
    final archiveBytes = _buildTestArchive();
    final archiveSha = '${await sha256.bind(Stream.value(archiveBytes)).first}';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/bad') {
        request.response.headers.contentType = ContentType(
          'application',
          'zip',
        );
        request.response.contentLength = archiveBytes.length;
        try {
          for (var offset = 0; offset < archiveBytes.length; offset += 100) {
            request.response.add(
              archiveBytes.sublist(
                offset,
                offset + 100 < archiveBytes.length
                    ? offset + 100
                    : archiveBytes.length,
              ),
            );
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        } catch (_) {
          // The client intentionally closes the slow response.
        }
        return;
      } else {
        request.response.headers.contentType = ContentType(
          'application',
          'zip',
        );
        request.response.contentLength = archiveBytes.length;
        request.response.add(archiveBytes);
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final home = await Directory.systemTemp.createTemp('jm-model-install-');
    addTearDown(() => home.delete(recursive: true));
    final origin = 'http://${server.address.address}:${server.port}';
    final model = _downloadModel(
      urls: ['$origin/bad', '$origin/good'],
      archiveBytes: archiveBytes.length,
      sha256Value: archiveSha,
      extractedBytes: 3 + 7 + 3 + 64,
    );

    final installed = await installSuperResolutionModel(
      homeDir: home.path,
      model: model,
      stallTimeout: const Duration(milliseconds: 300),
      minimumSpeedWindow: const Duration(milliseconds: 70),
      minimumBytesPerSecond: 1024 * 1024,
    );
    expect(
      await File(
        '$installed${Platform.pathSeparator}$superResolutionParamFileName',
      ).readAsString(),
      'param',
    );
    expect(
      await File(
        '$installed${Platform.pathSeparator}$superResolutionWeightsFileName',
      ).readAsString(),
      'weights',
    );
    expect(
      await File('$installed${Platform.pathSeparator}install.json').exists(),
      isTrue,
    );
  });
}
