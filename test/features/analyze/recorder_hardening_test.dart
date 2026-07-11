import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/clip_recorder.dart';
import 'package:music_theory/features/learn/audio/chord_audio.dart';

/// Round 101 — the round-100 review's two adjacent NOTEs, closed:
/// (1) `startRecording` re-entrancy: a second start() during the in-flight
///     await must NOT run a second mic attempt (it could overwrite the live
///     subscription without cancelling the first);
/// (2) the Backing pad cache must be bounded (every A4 × string pair used
///     to add a ~130 KB WAV forever).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent start() calls are single-flight — one mic attempt only',
      () async {
    var permissionChecks = 0;
    final recorder = ClipRecorder(ensurePermission: () async {
      permissionChecks++;
      // Yield so the second start() genuinely overlaps the first.
      await Future<void>.delayed(Duration.zero);
      return false; // denied — never touches the real mic in tests
    });

    final first = recorder.start();
    final second = recorder.start(); // fired while the first is in flight
    expect(await first, MicStart.denied);
    expect(await second, MicStart.denied);
    expect(permissionChecks, 1,
        reason: 'the overlapping call must join the in-flight attempt');

    // After the attempt settles, a fresh start is a fresh attempt.
    expect(await recorder.start(), MicStart.denied);
    expect(permissionChecks, 2);
  });

  test('the pad cache is bounded — old entries are evicted', () async {
    final backing = Backing();
    // Fire-and-forget dispose (never await it in tests — round 94 lesson).
    addTearDown(() {
      unawaited(backing.dispose());
    });
    for (var i = 0; i < Backing.maxCachedPads + 10; i++) {
      await backing.playTone(100.0 + i);
    }
    expect(backing.cacheSize, Backing.maxCachedPads);
  });
}
