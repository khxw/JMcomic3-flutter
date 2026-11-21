import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:jmcomic3/basic/methods.dart';

const superResolutionManifestUrls = [
  'https://raw.githubusercontent.com/khxw/JMcomic3-flutter/main/models/super_resolution/manifest.json',
  'https://gh-proxy.com/https://raw.githubusercontent.com/khxw/JMcomic3-flutter/main/models/super_resolution/manifest.json',
];
const _bundledManifestAsset = 'lib/assets/super_resolution_manifest.json';
const _manifestSchema = 1;
const _maxArchiveBytes = 512 * 1024 * 1024;
const superResolutionParamFileName = 'scale2.0x_model.param';
const superResolutionWeightsFileName = 'scale2.0x_model.bin';

class InstalledSuperResolutionModel {
  final String id;
  final String version;
  final Directory directory;

  const InstalledSuperResolutionModel({
    required this.id,
    required this.version,
    required this.directory,
  });

  File get paramFile => File(
        '${directory.path}${Platform.pathSeparator}$superResolutionParamFileName',
      );

  File get weightsFile => File(
        '${directory.path}${Platform.pathSeparator}$superResolutionWeightsFileName',
      );
}

class SuperResolutionModel {
  final String id;
  final String version;
  final String name;
  final String description;
  final int scale;
  final List<String> downloadUrls;
  final String sha256;
  final int archiveBytes;
  final int extractedBytes;
  final String licenseName;
  final String licenseUrl;

  const SuperResolutionModel({
    required this.id,
    required this.version,
    required this.name,
    required this.description,
    required this.scale,
    required this.downloadUrls,
    required this.sha256,
    required this.archiveBytes,
    required this.extractedBytes,
    required this.licenseName,
    required this.licenseUrl,
  });

  factory SuperResolutionModel.fromJson(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final version = '${json['version'] ?? ''}'.trim();
    final name = '${json['name'] ?? ''}'.trim();
    final sha = '${json['sha256'] ?? ''}'.trim().toLowerCase();
    final urls = <String>{
      if (json['download_url'] != null) '${json['download_url']}'.trim(),
      if (json['download_urls'] is Iterable)
        for (final value in json['download_urls'] as Iterable) '$value'.trim(),
    }.where((value) => value.isNotEmpty).toList(growable: false);
    final validId = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$').hasMatch(id);
    final validVersion =
        RegExp(r'^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$').hasMatch(version);
    final validSha = RegExp(r'^[0-9a-f]{64}$').hasMatch(sha);
    final scale = (json['scale'] as num?)?.toInt() ?? 0;
    final archiveBytes = (json['archive_bytes'] as num?)?.toInt() ?? 0;
    final extractedBytes = (json['extracted_bytes'] as num?)?.toInt() ?? 0;
    final licenseName = '${json['license_name'] ?? ''}'.trim();
    final licenseUrl = '${json['license_url'] ?? ''}'.trim();
    if (!validId ||
        !validVersion ||
        name.isEmpty ||
        !validSha ||
        urls.isEmpty ||
        urls.any((url) => !url.startsWith('https://')) ||
        scale < 1 ||
        scale > 4 ||
        archiveBytes <= 0 ||
        archiveBytes > _maxArchiveBytes ||
        extractedBytes <= 0 ||
        extractedBytes > _maxArchiveBytes ||
        licenseName.isEmpty ||
        !licenseUrl.startsWith('https://')) {
      throw const FormatException('invalid super-resolution model entry');
    }
    return SuperResolutionModel(
      id: id,
      version: version,
      name: name,
      description: '${json['description'] ?? ''}'.trim(),
      scale: scale,
      downloadUrls: urls,
      sha256: sha,
      archiveBytes: archiveBytes,
      extractedBytes: extractedBytes,
      licenseName: licenseName,
      licenseUrl: licenseUrl,
    );
  }
}

List<SuperResolutionModel> parseSuperResolutionManifest(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map || decoded['schema'] != _manifestSchema) {
    throw const FormatException('unsupported model manifest');
  }
  final models = decoded['models'];
  if (models is! Iterable) {
    throw const FormatException('models must be an array');
  }
  final result = <SuperResolutionModel>[];
  final seen = <String>{};
  for (final item in models) {
    if (item is! Map) continue;
    final model = SuperResolutionModel.fromJson(
      Map<String, dynamic>.from(item),
    );
    if (seen.add('${model.id}@${model.version}')) result.add(model);
  }
  return List.unmodifiable(result);
}

Future<List<SuperResolutionModel>> loadSuperResolutionModels() async {
  for (final url in superResolutionManifestUrls) {
    try {
      final raw = '${await methods.httpGet(url)}'.trim();
      final models = parseSuperResolutionManifest(raw);
      if (models.isNotEmpty) return models;
    } catch (_) {
      // Try the next mirror and then the bundled fallback.
    }
  }
  final bundled = await rootBundle.loadString(_bundledManifestAsset);
  return parseSuperResolutionManifest(bundled);
}

Directory superResolutionModelDirectory(String homeDir, String modelId) =>
    Directory(
      '${Directory(homeDir).path}${Platform.pathSeparator}'
      'super_resolution_models${Platform.pathSeparator}$modelId',
    );

bool isSuperResolutionModelInstalled(
  String homeDir,
  SuperResolutionModel model,
) {
  final versionDirectory = Directory(
    '${superResolutionModelDirectory(homeDir, model.id).path}'
    '${Platform.pathSeparator}${model.version}',
  );
  return File(
        '${versionDirectory.path}${Platform.pathSeparator}install.json',
      ).existsSync() &&
      File(
        '${versionDirectory.path}'
        '${Platform.pathSeparator}$superResolutionParamFileName',
      ).existsSync() &&
      File(
        '${versionDirectory.path}'
        '${Platform.pathSeparator}$superResolutionWeightsFileName',
      ).existsSync();
}

Future<InstalledSuperResolutionModel?> findInstalledSuperResolutionModel(
  String homeDir,
) async {
  final root = Directory(
    '${Directory(homeDir).path}${Platform.pathSeparator}'
    'super_resolution_models',
  );
  if (!await root.exists()) return null;

  final candidates = <({
    DateTime modified,
    InstalledSuperResolutionModel model,
  })>[];
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! Directory) continue;
    await for (final versionEntity in entity.list(followLinks: false)) {
      if (versionEntity is! Directory) continue;
      final installFile = File(
        '${versionEntity.path}${Platform.pathSeparator}install.json',
      );
      final paramFile = File(
        '${versionEntity.path}'
        '${Platform.pathSeparator}$superResolutionParamFileName',
      );
      final weightsFile = File(
        '${versionEntity.path}'
        '${Platform.pathSeparator}$superResolutionWeightsFileName',
      );
      if (!await installFile.exists() ||
          !await paramFile.exists() ||
          !await weightsFile.exists()) {
        continue;
      }
      try {
        final metadata = jsonDecode(await installFile.readAsString());
        if (metadata is! Map) continue;
        final id = '${metadata['id'] ?? ''}'.trim();
        final version = '${metadata['version'] ?? ''}'.trim();
        if (id.isEmpty || version.isEmpty) continue;
        final installedAt = (metadata['installed_at'] as num?)?.toInt() ?? 0;
        candidates.add((
          modified: installedAt > 0
              ? DateTime.fromMillisecondsSinceEpoch(installedAt)
              : await installFile.lastModified(),
          model: InstalledSuperResolutionModel(
            id: id,
            version: version,
            directory: versionEntity,
          ),
        ));
      } catch (_) {
        // Ignore incomplete or corrupted installations and try other models.
      }
    }
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.modified.compareTo(a.modified));
  return candidates.first.model;
}

Future<void> deleteSuperResolutionModel(
  String homeDir,
  String modelId,
) async {
  final directory = superResolutionModelDirectory(homeDir, modelId);
  if (await directory.exists()) await directory.delete(recursive: true);
}

typedef SuperResolutionDownloadProgress = void Function(
  int received,
  int? total,
);

Future<String> installSuperResolutionModel({
  required String homeDir,
  required SuperResolutionModel model,
  SuperResolutionDownloadProgress? onProgress,
}) async {
  final modelRoot = superResolutionModelDirectory(homeDir, model.id);
  await modelRoot.create(recursive: true);
  final staging = Directory(
    '${modelRoot.path}${Platform.pathSeparator}'
    '.install-${DateTime.now().microsecondsSinceEpoch}',
  );
  await staging.create(recursive: true);
  final archiveFile = File(
    '${staging.path}${Platform.pathSeparator}model.zip.part',
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final response = await _openDownload(client, model.downloadUrls);
    final total = response.contentLength > 0 ? response.contentLength : null;
    var received = 0;
    final sink = archiveFile.openWrite();
    try {
      await for (final chunk in response) {
        received += chunk.length;
        if (received > model.archiveBytes) {
          throw const FormatException('model archive is larger than declared');
        }
        sink.add(chunk);
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (received != model.archiveBytes) {
      throw const FormatException('model archive size mismatch');
    }
    final digest = await sha256.bind(archiveFile.openRead()).first;
    if ('$digest' != model.sha256) {
      throw const FormatException('model archive checksum mismatch');
    }
    await _extractModelArchive(archiveFile, staging, model);
    final destination = Directory(
      '${modelRoot.path}${Platform.pathSeparator}${model.version}',
    );
    if (await destination.exists()) await destination.delete(recursive: true);
    await staging.rename(destination.path);
    return destination.path;
  } finally {
    client.close(force: true);
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}

Future<HttpClientResponse> _openDownload(
  HttpClient client,
  List<String> urls,
) async {
  Object? lastError;
  for (final url in urls) {
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'JMComic3-Mod model downloader',
      );
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) return response;
      await response.drain<void>();
      lastError =
          HttpException('HTTP ${response.statusCode}', uri: request.uri);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? const HttpException('no model download URL');
}

Future<void> _extractModelArchive(
  File archiveFile,
  Directory staging,
  SuperResolutionModel model,
) async {
  final bytes = await archiveFile.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  var extractedBytes = 0;
  for (final entry in archive.files) {
    if (!entry.isFile) continue;
    if (entry.isSymbolicLink) {
      throw const FormatException('model archive contains a symbolic link');
    }
    final normalized = entry.name.replaceAll('\\', '/').trim();
    final segments = normalized.split('/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        segments.any((segment) => segment.isEmpty || segment == '..')) {
      throw const FormatException('unsafe model archive path');
    }
    extractedBytes += entry.size;
    if (extractedBytes > model.extractedBytes) {
      throw const FormatException('model archive extracts too much data');
    }
    final target = File(
      '${staging.path}${Platform.pathSeparator}'
      '${segments.join(Platform.pathSeparator)}',
    );
    await target.parent.create(recursive: true);
    final content = entry.readBytes();
    if (content == null) {
      throw const FormatException('model archive entry has no content');
    }
    await target.writeAsBytes(content, flush: true);
  }
  if (!await File(
        '${staging.path}'
        '${Platform.pathSeparator}$superResolutionParamFileName',
      ).exists() ||
      !await File(
        '${staging.path}'
        '${Platform.pathSeparator}$superResolutionWeightsFileName',
      ).exists()) {
    throw const FormatException('model archive is missing required files');
  }
  await File(
    '${staging.path}${Platform.pathSeparator}install.json',
  ).writeAsString(
    jsonEncode({
      'id': model.id,
      'version': model.version,
      'sha256': model.sha256,
      'installed_at': DateTime.now().millisecondsSinceEpoch,
    }),
    flush: true,
  );
}

String formatModelBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
