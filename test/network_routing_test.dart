import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/network_api_host.dart';
import 'package:jmcomic3/configs/network_cdn_host.dart';
import 'package:jmcomic3/configs/network_ping.dart';

const _channel = MethodChannel('methods');

String _response(Object? data) => jsonEncode({
      'error_message': '',
      'response_data': data is String ? data : jsonEncode(data),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fastest successful host wins and failed probes are ignored', () async {
    final selected = await selectFastestHost(
      ['slow.example.com', 'failed.example.com', 'fast.example.com'],
      (host) async {
        if (host == 'failed.example.com') {
          throw StateError('offline');
        }
        await Future<void>.delayed(
          Duration(milliseconds: host.startsWith('fast') ? 5 : 25),
        );
        return host.startsWith('fast') ? 18 : 240;
      },
      timeout: const Duration(milliseconds: 100),
    );

    expect(selected?.host, 'fast.example.com');
    expect(selected?.milliseconds, 18);
  });

  test('API and CDN startup automatically save the fastest routes', () async {
    final savedApiHosts = <String>[];
    final savedCdnHosts = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      final method = request['method'];
      final params = '${request['params'] ?? ''}';
      switch (method) {
        case 'load_api_host_list':
          return _response(jsonEncode([
            'slow-api.example.com',
            'fast-api.example.com',
          ]));
        case 'load_api_host':
          return _response(jsonEncode('slow-api.example.com'));
        case 'load_cdn_host':
          return _response(jsonEncode('cdn-current.example.com'));
        case 'ping_server':
          return _response(
            params == 'fast-api.example.com'
                ? '18'
                : params == 'slow-api.example.com'
                    ? '260'
                    : '420',
          );
        case 'ping_cdn':
          return _response(
            params == 'cdn-msp3.jmapiproxy2.cc'
                ? '12'
                : params == 'cdn-current.example.com'
                    ? '180'
                    : '360',
          );
        case 'save_api_host':
          savedApiHosts.add(params);
          return _response('');
        case 'save_cdn_host':
          savedCdnHosts.add(params);
          return _response('');
        default:
          return _response('');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await initApiHost();
    await initCdnHost();

    expect(currentApiHostName, 'fast-api.example.com');
    expect(currentCdnHostName, 'cdn-msp3.jmapiproxy2.cc');
    expect(savedApiHosts.last, 'fast-api.example.com');
    expect(savedCdnHosts.last, 'cdn-msp3.jmapiproxy2.cc');

    final rotated = await rotateApiHostAfterInvalidResponse();
    expect(rotated, isTrue);
    expect(currentApiHostName, isNot('fast-api.example.com'));
    expect(savedApiHosts.last, currentApiHostName);
  });
}
