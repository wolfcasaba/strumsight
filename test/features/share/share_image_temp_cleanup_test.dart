// Regression: ShareService.shareImage used to write the captured PNG straight
// into Directory.systemTemp under a deterministic name and never delete it, so
// every card share left a readable copy of the user's practice card on disk
// (and a second share of the same card silently overwrote a file another
// share might still be reading). shareExportFile already owned its temp
// lifecycle with a try/finally; shareImage now mirrors it — a private
// per-share directory, deleted whether the share succeeds or throws.
//
// Exercises the REAL production method against a mocked
// `dev.fluttercommunity.plus/share` method channel, the same way
// share_service_test.dart does, so the contract is proven on the actual
// implementation rather than a stand-in.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/share/public.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final boundaryKey = GlobalKey();

  final sharedPaths = <String>[];

  void mockShare({bool fail = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = (call.arguments as Map).cast<String, dynamic>();
          sharedPaths.addAll(
            (arguments['paths'] as List<Object?>).cast<String>(),
          );
          if (fail) throw PlatformException(code: 'share_failed');
          return 'shared';
        });
  }

  Widget host() => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        key: boundaryKey,
        child: Container(width: 64, height: 64, color: const Color(0xFF123456)),
      ),
    ),
  );

  // A run against the pre-fix implementation strands
  // `<systemTemp>/<fileName>` — exactly what this file asserts must never
  // appear. Clear that stale copy up front so the assertion measures THIS
  // run, not a previous one.
  setUp(() {
    sharedPaths.clear();
    for (final name in const <String>[
      'cleanup-success.png',
      'cleanup-failure.png',
      'cleanup-collision.png',
    ]) {
      final stale = File('${Directory.systemTemp.path}/$name');
      if (stale.existsSync()) stale.deleteSync();
    }
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('a successful image share leaves nothing on disk', (
    tester,
  ) async {
    mockShare();
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => const ShareService().shareImage(
        boundaryKey: boundaryKey,
        caption: 'caption',
        fileName: 'cleanup-success.png',
      ),
    );

    expect(sharedPaths, hasLength(1));
    final shared = File(sharedPaths.single);
    expect(
      shared.parent.path,
      isNot(Directory.systemTemp.path),
      reason: 'the PNG must not sit directly in the shared system temp dir',
    );
    expect(shared.existsSync(), isFalse);
    expect(shared.parent.existsSync(), isFalse);
    expect(
      File('${Directory.systemTemp.path}/cleanup-success.png').existsSync(),
      isFalse,
    );
  });

  testWidgets('a failed image share still cleans up its temp directory', (
    tester,
  ) async {
    mockShare(fail: true);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    Object? thrown;
    await tester.runAsync(() async {
      try {
        await const ShareService().shareImage(
          boundaryKey: boundaryKey,
          caption: 'caption',
          fileName: 'cleanup-failure.png',
        );
      } catch (error) {
        thrown = error;
      }
    });

    expect(thrown, isA<PlatformException>());
    expect(sharedPaths, hasLength(1));
    final shared = File(sharedPaths.single);
    expect(shared.existsSync(), isFalse);
    expect(shared.parent.existsSync(), isFalse);
  });

  testWidgets('two shares of the same card never collide on one path', (
    tester,
  ) async {
    mockShare();
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    for (var i = 0; i < 2; i++) {
      await tester.runAsync(
        () => const ShareService().shareImage(
          boundaryKey: boundaryKey,
          caption: 'caption',
          fileName: 'cleanup-collision.png',
        ),
      );
    }

    expect(sharedPaths, hasLength(2));
    expect(sharedPaths.first, isNot(sharedPaths.last));
  });
}
