import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/github_download_mirrors.dart';

const _superResolutionManifestOfficialUrl =
    'https://raw.githubusercontent.com/khxw/JMcomic3-flutter/main/models/super_resolution/manifest.json';
final superResolutionManifestUrls = List<String>.unmodifiable(
  githubDownloadCandidates([_superResolutionManifestOfficialUrl]),
);
const _bundledManifestAsset = 'lib/assets/super_resolution_manifest.json';
const _manifestSchema = 2;
const _maxArchiveBytes = 512 * 1024 * 1024;
const _modelRequestTimeout = Duration(seconds: 12);
const _modelProgressInterval = Duration(milliseconds: 120);
const _modelMinimumSpeedWindow = Duration(seconds: 4);
const _modelMinimumBytesPerSecond = 64 * 1024;
const superResolutionParamFileName = 'scale2.0x_model.param';
const superResolutionWeightsFileName = 'scale2.0x_model.bin';
const superResolutionModelFormatRealCugan = 'realcugan-ncnn-v1';

class InstalledSuperResolutionModel {
  final String id;
  final String version;
  final String modelFormat;
  final String inputName;
  final String outputName;
  final int prepadding;
  final Directory directory;

  const InstalledSuperResolutionModel({
    required this.id,
    required this.version,
    required this.modelFormat,
    required this.inputName,
    required this.outputName,
    required this.prepadding,
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
  final String modelFormat;
  final String inputName;
  final String outputName;
  final int prepadding;
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
    required this.modelFormat,
    required this.inputName,
    required this.outputName,
    required this.prepadding,
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
    final modelFormat = '${json['model_format'] ?? ''}'.trim();
    final inputName = '${json['input_name'] ?? ''}'.trim();
    final outputName = '${json['output_name'] ?? ''}'.trim();
    final prepadding = (json['prepadding'] as num?)?.toInt() ?? -1;
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
        modelFormat != superResolutionModelFormatRealCugan ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(inputName) ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(outputName) ||
        prepadding < 0 ||
        prepadding > 64 ||
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
      modelFormat: modelFormat,
      inputName: inputName,
      outputName: outputName,
      prepadding: prepadding,
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
      final raw =
          '${await methods.httpGet(url).timeout(_modelRequestTimeout)}'.trim();
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
  final installFile = File(
    '${versionDirectory.path}${Platform.pathSeparator}install.json',
  );
  if (!installFile.existsSync() ||
      !File(
        '${versionDirectory.path}'
        '${Platform.pathSeparator}$superResolutionParamFileName',
      ).existsSync() ||
      !File(
        '${versionDirectory.path}'
        '${Platform.pathSeparator}$superResolutionWeightsFileName',
      ).existsSync()) {
    return false;
  }
  try {
    final metadata = jsonDecode(installFile.readAsStringSync());
    return metadata is Map &&
        '${metadata['id'] ?? ''}' == model.id &&
        '${metadata['version'] ?? ''}' == model.version &&
        '${metadata['model_format'] ?? ''}' == model.modelFormat &&
        '${metadata['input_name'] ?? ''}' == model.inputName &&
        '${metadata['output_name'] ?? ''}' == model.outputName &&
        (metadata['prepadding'] as num?)?.toInt() == model.prepadding;
  } catch (_) {
    return false;
  }
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
        final modelFormat = '${metadata['model_format'] ?? ''}'.trim();
        final inputName = '${metadata['input_name'] ?? ''}'.trim();
        final outputName = '${metadata['output_name'] ?? ''}'.trim();
        final prepadding = (metadata['prepadding'] as num?)?.toInt() ?? -1;
        if (id.isEmpty ||
            version.isEmpty ||
            modelFormat != superResolutionModelFormatRealCugan ||
            inputName.isEmpty ||
            outputName.isEmpty ||
            prepadding < 0 ||
            prepadding > 64) {
          continue;
        }
        final installedAt = (metadata['installed_at'] as num?)?.toInt() ?? 0;
        candidates.add((
          modified: installedAt > 0
              ? DateTime.fromMillisecondsSinceEpoch(installedAt)
              : await installFile.lastModified(),
          model: InstalledSuperResolutionModel(
            id: id,
            version: version,
            modelFormat: modelFormat,
            inputName: inputName,
            outputName: outputName,
            prepadding: prepadding,
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
  Duration stallTimeout = _modelRequestTimeout,
  Duration minimumSpeedWindow = _modelMinimumSpeedWindow,
  int minimumBytesPerSecond = _modelMinimumBytesPerSecond,
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
  final client = HttpClient()..connectionTimeout = _modelRequestTimeout;
  try {
    Object? lastError;
    var downloaded = false;
    final candidates = githubDownloadCandidates(model.downloadUrls);
    for (var index = 0; index < candidates.length; index++) {
      final url = candidates[index];
      try {
        await _downloadModelArchive(
          client: client,
          uri: Uri.parse(url),
          archiveFile: archiveFile,
          model: model,
          onProgress: onProgress,
          stallTimeout: stallTimeout,
          minimumSpeedWindow: minimumSpeedWindow,
          minimumBytesPerSecond: minimumBytesPerSecond,
          enforceMinimumSpeed: index < candidates.length - 1,
        );
        final digest = await sha256.bind(archiveFile.openRead()).first;
        if ('$digest' != model.sha256) {
          throw const FormatException('model archive checksum mismatch');
        }
        downloaded = true;
        break;
      } catch (error) {
        lastError = error;
        onProgress?.call(0, model.archiveBytes);
        if (await archiveFile.exists()) await archiveFile.delete();
      }
    }
    if (!downloaded) {
      throw lastError ?? const HttpException('no model download URL');
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

Future<void> _downloadModelArchive({
  required HttpClient client,
  required Uri uri,
  required File archiveFile,
  required SuperResolutionModel model,
  required Duration stallTimeout,
  required Duration minimumSpeedWindow,
  required int minimumBytesPerSecond,
  required bool enforceMinimumSpeed,
  SuperResolutionDownloadProgress? onProgress,
}) async {
  onProgress?.call(0, model.archiveBytes);
  final request = await client.getUrl(uri).timeout(_modelRequestTimeout);
  request.followRedirects = true;
  request.headers.set(
    HttpHeaders.userAgentHeader,
    'JMComic3-Mod model downloader',
  );
  final response = await request.close().timeout(_modelRequestTimeout);
  if (response.statusCode != HttpStatus.ok) {
    await response.drain<void>();
    throw HttpException('HTTP ${response.statusCode}', uri: uri);
  }

  final total = response.contentLength > 0 ? response.contentLength : null;
  var received = 0;
  var lastProgressAt = 0;
  final startedAt = DateTime.now();
  final sink = archiveFile.openWrite();
  try {
    await for (final chunk in response.timeout(stallTimeout)) {
      received += chunk.length;
      if (received > model.archiveBytes) {
        throw const FormatException('model archive is larger than declared');
      }
      sink.add(chunk);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (received == model.archiveBytes ||
          now - lastProgressAt >= _modelProgressInterval.inMilliseconds) {
        lastProgressAt = now;
        onProgress?.call(received, total ?? model.archiveBytes);
      }
      final elapsed = DateTime.now().difference(startedAt);
      if (enforceMinimumSpeed &&
          elapsed >= minimumSpeedWindow &&
          received / (elapsed.inMilliseconds / 1000) < minimumBytesPerSecond) {
        throw HttpException(
          'model download speed below $minimumBytesPerSecond bytes/s',
          uri: uri,
        );
      }
    }
  } finally {
    await sink.flush();
    await sink.close();
  }
  if (received != model.archiveBytes) {
    throw const FormatException('model archive size mismatch');
  }
  if (total != null && total != model.archiveBytes) {
    throw const FormatException('model archive response size mismatch');
  }
  onProgress?.call(received, model.archiveBytes);
}

@visibleForTesting
Future<void> downloadSuperResolutionArchiveForTest({
  required Uri uri,
  required File archiveFile,
  required SuperResolutionModel model,
  Duration stallTimeout = const Duration(milliseconds: 200),
}) async {
  final client = HttpClient()..connectionTimeout = _modelRequestTimeout;
  try {
    await _downloadModelArchive(
      client: client,
      uri: uri,
      archiveFile: archiveFile,
      model: model,
      stallTimeout: stallTimeout,
      minimumSpeedWindow: const Duration(seconds: 4),
      minimumBytesPerSecond: _modelMinimumBytesPerSecond,
      enforceMinimumSpeed: false,
    );
  } finally {
    client.close(force: true);
  }
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
      'model_format': model.modelFormat,
      'input_name': model.inputName,
      'output_name': model.outputName,
      'prepadding': model.prepadding,
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
