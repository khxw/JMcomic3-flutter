import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class DownloadPausedException implements Exception {
  const DownloadPausedException();

  @override
  String toString() => 'download paused';
}

class DownloadControl {
  bool _pauseRequested = false;

  bool get pauseRequested => _pauseRequested;

  void pause() {
    _pauseRequested = true;
  }
}

class AppHttpClient {
  static final HttpClient _client = HttpClient()
    ..autoUncompress = true
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 20)
    ..maxConnectionsPerHost = 6
    ..userAgent = "JMComic3Mod/Flutter";

  static Future<String> getText(
    String url, {
    Map<String, String>? headers,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration requestTimeout = const Duration(seconds: 15),
    int retries = 1,
    bool allowMalformedUtf8 = true,
  }) async {
    final uri = Uri.parse(url);
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final request = await _client.getUrl(uri).timeout(
              connectTimeout,
            );
        request.followRedirects = true;
        request.maxRedirects = 5;
        headers?.forEach((key, value) {
          request.headers.set(key, value);
        });

        final response = await request.close().timeout(requestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            "HTTP ${response.statusCode}",
            uri: uri,
          );
        }

        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
        }
        return utf8.decode(
          builder.takeBytes(),
          allowMalformed: allowMalformedUtf8,
        );
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on HandshakeException catch (e) {
        lastError = e;
      } on HttpException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = e;
      }

      if (attempt < retries) {
        await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }

    throw lastError ?? StateError("http get failed: $url");
  }

  static Future<String?> getTextOrNull(
    String url, {
    Map<String, String>? headers,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration requestTimeout = const Duration(seconds: 15),
    int retries = 1,
    bool allowMalformedUtf8 = true,
  }) async {
    try {
      return await getText(
        url,
        headers: headers,
        connectTimeout: connectTimeout,
        requestTimeout: requestTimeout,
        retries: retries,
        allowMalformedUtf8: allowMalformedUtf8,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> downloadFile(
    String url,
    File destination, {
    Map<String, String>? headers,
    void Function(double? progress)? onProgress,
    bool resume = false,
    DownloadControl? control,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration requestTimeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse(url);
    await destination.parent.create(recursive: true);
    final partial = File('${destination.path}.part');
    var existingBytes =
        resume && await partial.exists() ? await partial.length() : 0;
    if (!resume && await partial.exists()) {
      await partial.delete();
      existingBytes = 0;
    }
    if (control?.pauseRequested == true) {
      throw const DownloadPausedException();
    }

    final request = await _client.getUrl(uri).timeout(connectTimeout);
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (existingBytes > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
    }
    headers?.forEach((key, value) {
      request.headers.set(key, value);
    });

    final response = await request.close().timeout(requestTimeout);
    if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
        existingBytes > 0) {
      final total = _totalFromContentRange(
        response.headers.value(HttpHeaders.contentRangeHeader),
      );
      await response.drain<void>();
      if (total != null && existingBytes == total) {
        if (await destination.exists()) {
          await destination.delete();
        }
        await partial.rename(destination.path);
        onProgress?.call(1);
        return;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        "HTTP ${response.statusCode}",
        uri: uri,
      );
    }

    var append = false;
    int? total;
    if (response.statusCode == HttpStatus.partialContent && existingBytes > 0) {
      final contentRange = response.headers.value(
        HttpHeaders.contentRangeHeader,
      );
      final range = _parseContentRange(contentRange);
      if (range == null || range.start != existingBytes) {
        throw const FormatException('invalid partial download range');
      }
      append = true;
      total = range.total;
    } else {
      // The mirror ignored Range or the file is starting from zero.
      existingBytes = 0;
      append = false;
      total = response.contentLength > 0 ? response.contentLength : null;
    }
    if (control?.pauseRequested == true) {
      await response.drain<void>();
      throw const DownloadPausedException();
    }

    final sink = partial.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    var sinkClosed = false;
    var received = 0;
    try {
      void reportProgress() {
        if (total == null || total <= 0) {
          onProgress?.call(null);
          return;
        }
        onProgress?.call(
          ((existingBytes + received) / total).clamp(0, 1).toDouble(),
        );
      }

      reportProgress();
      await for (final chunk in response) {
        if (control?.pauseRequested == true) {
          throw const DownloadPausedException();
        }
        sink.add(chunk);
        received += chunk.length;
        reportProgress();
      }
      await sink.flush();
      await sink.close();
      sinkClosed = true;
      if (total != null && existingBytes + received != total) {
        throw HttpException(
          "Incomplete download: ${existingBytes + received}/$total bytes",
          uri: uri,
        );
      }
      if (await destination.exists()) {
        await destination.delete();
      }
      await partial.rename(destination.path);
      onProgress?.call(1);
    } catch (_) {
      if (!sinkClosed) {
        try {
          await sink.flush();
        } catch (_) {}
        try {
          await sink.close();
        } catch (_) {}
      }
      rethrow;
    }
  }

  static ({int start, int? total})? _parseContentRange(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$').firstMatch(
      value.trim(),
    );
    if (match == null) return null;
    final totalRaw = match.group(3);
    return (
      start: int.tryParse(match.group(1)!) ?? -1,
      total: totalRaw == '*' ? null : int.tryParse(totalRaw!),
    );
  }

  static int? _totalFromContentRange(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^bytes\s+\*/(\d+)$').firstMatch(value.trim());
    return int.tryParse(match?.group(1) ?? '');
  }
}
