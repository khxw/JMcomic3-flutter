import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('super-resolution uses the native method channel directly', () async {
    const channel = MethodChannel('methods');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'superResolutionImage':
          return '/tmp/upscaled.jpg';
        case 'clearSuperResolutionCache':
          return null;
        case 'superResolutionCapabilities':
          return <String, Object>{
            'vulkan_available': true,
            'device_name': 'Test Vulkan GPU',
          };
        default:
          throw StateError('unexpected bridge method: ${call.method}');
      }
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(channel, null),
    );

    final output = await methods.superResolutionImage(
      inputPath: '/tmp/source.jpg',
      modelDirectory: '/tmp/model',
      threads: 4,
      tileSize: 384,
      backend: 'gpu',
    );
    final capabilities = await methods.superResolutionCapabilities();
    await methods.clearSuperResolutionCache();

    expect(output, '/tmp/upscaled.jpg');
    expect(capabilities, {
      'vulkan_available': true,
      'device_name': 'Test Vulkan GPU',
    });
    expect(calls.map((call) => call.method), [
      'superResolutionImage',
      'superResolutionCapabilities',
      'clearSuperResolutionCache',
    ]);
    expect(calls.first.arguments, {
      'input_path': '/tmp/source.jpg',
      'model_directory': '/tmp/model',
      'threads': 4,
      'tile_size': 384,
      'backend': 'gpu',
    });
  });
}
