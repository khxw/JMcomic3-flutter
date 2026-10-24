import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/versions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('update checks and cached update state stay disabled', () async {
    expect(updatesTemporarilyDisabled, isTrue);
    await initVersion();
    expect(RegExp(r'^v\d+\.\d+\.\d+\+\d+$').hasMatch(currentVersion()), isTrue);
    expect(latestVersion, isNull);
    expect(latestVersionName, isNull);
    expect(latestVersionInfo(), isNull);
    await autoCheckNewVersion();
    await silentCheckNewVersion();
    expect(latestVersion, isNull);
  });
}
