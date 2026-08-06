import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera platform declarations remain optional and privacy-precise', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(manifest, contains('android.permission.CAMERA'));
    expect(manifest, contains('android.hardware.camera'));
    expect(manifest, contains('android:required="false"'));
    expect(plist, contains('<key>NSCameraUsageDescription</key>'));

    final usageDescription = RegExp(
      r'<key>NSCameraUsageDescription</key>\s*<string>(.*?)</string>',
      dotAll: true,
    ).firstMatch(plist);
    expect(usageDescription, isNotNull);

    final usageText = usageDescription!.group(1)!.toLowerCase();
    expect(usageText, contains('on your device'));
    expect(usageText, contains('no recording'));
    for (final forbiddenWord in const ['upload', 'cloud', 'server']) {
      expect(usageText, isNot(contains(forbiddenWord)));
    }
  });
}
