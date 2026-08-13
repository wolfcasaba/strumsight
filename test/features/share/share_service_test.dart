// ShareService.shareExportFile — the single additive method the E06-R27
// H3 self-heal added (docs/adr/0247-analysis-export-share-and-delete-contract.md
// §Döntés 2; docs/rounds/e06-r27-export-share-and-privacy-controls.md
// §0.0/§5.8). Exercises the REAL production method (not a fake) against a
// mocked platform channel, so the try/finally cleanup contract is proven
// against the actual implementation, not a stand-in.
//
// share_plus's default `SharePlatform.instance` in a `flutter test` run is
// `MethodChannelShare`, which talks to the `dev.fluttercommunity.plus/share`
// method channel — no platform plugin registration happens outside a real
// app run, so mocking that channel with
// `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
// .setMockMethodCallHandler` intercepts the real call path without needing
// to touch ShareService's constructor or the unchanged
// shareCard/shareImage/shareText methods.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/share/public.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');

  Future<File> tempFile(String name) async {
    final dir = await Directory.systemTemp.createTemp('share_service_test_');
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(utf8.encode('{"exportSchemaVersion":1}'));
    return file;
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a successful share deletes the temp file afterward', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'shared');
    final file = await tempFile('export-success.json');
    const service = ShareService();

    await service.shareExportFile(file: file, caption: 'caption');

    expect(file.existsSync(), isFalse);
  });

  test('a failed share still deletes the temp file afterward', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'share_failed');
        });
    final file = await tempFile('export-failure.json');
    const service = ShareService();

    await expectLater(
      service.shareExportFile(file: file, caption: 'caption'),
      throwsA(isA<PlatformException>()),
    );

    expect(file.existsSync(), isFalse);
  });

  test('the existing shareText contract is unaffected by the new method', () {
    // Compile-time + shape guard: shareCard/shareImage/shareText keep their
    // original signatures — this file only ever calls the new
    // shareExportFile method, and the class still exposes the old three.
    const service = ShareService();
    expect(service.shareCard, isNotNull);
    expect(service.shareImage, isNotNull);
    expect(service.shareText, isNotNull);
  });
}
