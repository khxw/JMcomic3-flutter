import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/super_resolution_models.dart';

Map<String, Object> _model({String? sha}) => {
      'id': 'waifu2x-anime-2x',
      'version': '1.0.0',
      'name': 'Anime 2x',
      'description': 'Test model',
      'scale': 2,
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

void main() {
  test('super-resolution manifest validates and deduplicates models', () {
    final models = parseSuperResolutionManifest(jsonEncode({
      'schema': 1,
      'models': [_model(), _model()],
    }));

    expect(models, hasLength(1));
    expect(models.single.id, 'waifu2x-anime-2x');
    expect(models.single.scale, 2);
    expect(models.single.downloadUrls, hasLength(2));
  });

  test('super-resolution manifest rejects invalid checksums', () {
    expect(
      () => parseSuperResolutionManifest(jsonEncode({
        'schema': 1,
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
}
