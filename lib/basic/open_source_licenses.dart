import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

const _bundledLicenses = <({
  String asset,
  List<String> packages,
})>[
  (
    asset: 'third_party/ncnn/LICENSE.txt',
    packages: ['Tencent ncnn'],
  ),
  (
    asset: 'third_party/waifu2x-ncnn-vulkan/LICENSE.txt',
    packages: ['waifu2x-ncnn-vulkan'],
  ),
  (
    asset: 'third_party/zoomable_positioned_list/LICENSE',
    packages: ['zoomable_positioned_list'],
  ),
  (
    asset: 'third_party/zoomable_positioned_list/LICENSE.fuchsia',
    packages: ['zoomable_positioned_list Fuchsia components'],
  ),
];

/// Adds native and directly vendored component licenses to Flutter's generated
/// package license registry. Registration is idempotent because the registry
/// has process-wide lifetime.
Future<void> ensureOpenSourceLicensesRegistered() async {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final license in _bundledLicenses) {
      try {
        final text = await rootBundle.loadString(license.asset);
        yield LicenseEntryWithLineBreaks(license.packages, text);
      } catch (error) {
        // Flutter's generated package notices must remain available even if an
        // optional vendored license asset cannot be read.
        debugPrint(
          'Unable to load license asset ${license.asset}: ${error.runtimeType}',
        );
      }
    }
  });
}
