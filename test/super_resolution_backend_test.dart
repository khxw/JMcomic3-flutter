import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/super_resolution.dart';

void main() {
  test('automatic mode prefers Vulkan and falls back to native auto', () {
    expect(
      superResolutionBackendRequest(
        SuperResolutionBackendMode.auto,
        preload: false,
        vulkanAvailable: true,
      ),
      'auto',
    );
    expect(
      superResolutionBackendRequest(
        SuperResolutionBackendMode.auto,
        preload: true,
        vulkanAvailable: false,
      ),
      'auto',
    );
  });

  test('GPU mode never requests the CPU backend', () {
    expect(
      superResolutionBackendRequest(
        SuperResolutionBackendMode.gpu,
        preload: false,
        vulkanAvailable: true,
      ),
      'gpu',
    );
    expect(
      superResolutionBackendRequest(
        SuperResolutionBackendMode.gpu,
        preload: true,
        vulkanAvailable: true,
      ),
      'gpu',
    );
  });

  test('hybrid mode uses GPU for visible pages and CPU for preloads', () {
    expect(
      superResolutionBackendRequest(
        SuperResolutionBackendMode.hybrid,
        preload: false,
        vulkanAvailable: true,
      ),
      'gpu',
    );
    expect(
      superResolutionBackendRequest(
        SuperResolutionBackendMode.hybrid,
        preload: true,
        vulkanAvailable: true,
      ),
      'cpu',
    );
  });
}
