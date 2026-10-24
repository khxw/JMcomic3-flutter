import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    Duration connectTimeout = const Duration(seconds: 15),
    Duration requestTimeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse(url);
    final request = await _client.getUrl(uri).timeout(connectTimeout);
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
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

    await destination.parent.create(recursive: true);
    final partial = File('${destination.path}.part');
    if (await partial.exists()) {
      await partial.delete();
    }
    final sink = partial.openWrite();
    var received = 0;
    final total = response.contentLength > 0 ? response.contentLength : null;
    try {
      onProgress?.call(total == null ? null : 0);
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null) {
          onProgress?.call((received / total).clamp(0, 1).toDouble());
        }
      }
      await sink.flush();
      await sink.close();
      if (total != null && received != total) {
        throw HttpException(
          "Incomplete download: $received/$total bytes",
          uri: uri,
        );
      }
      if (await destination.exists()) {
        await destination.delete();
      }
      await partial.rename(destination.path);
      onProgress?.call(1);
    } catch (_) {
      await sink.close();
      if (await partial.exists()) {
        await partial.delete();
      }
      rethrow;
    }
  }
}
