import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/tuner/model/in_tune_lock.dart';

/// Round 85 — the "string locked in" moment. A single in-tune reading is
/// noise; holding it is the achievement. The lock engages after
/// [InTuneLock.holdReadings] consecutive in-tune readings of the SAME note,
/// fires exactly once (haptic/celebration), and re-arms when the pitch
/// drifts out or the player moves to another string.
void main() {
  test('locks after the hold count and fires exactly once', () {
    final lock = InTuneLock();
    var fired = 0;
    for (var i = 0; i < InTuneLock.holdReadings - 1; i++) {
      if (lock.feed(inTune: true, note: 'A')) fired++;
    }
    expect(fired, 0, reason: 'not held long enough yet');
    if (lock.feed(inTune: true, note: 'A')) fired++;
    expect(fired, 1);
    expect(lock.isLocked, isTrue);
    // Staying in tune keeps it locked but never re-fires.
    for (var i = 0; i < 10; i++) {
      if (lock.feed(inTune: true, note: 'A')) fired++;
    }
    expect(fired, 1);
  });

  test('drifting out of tune re-arms the lock', () {
    final lock = InTuneLock();
    for (var i = 0; i < InTuneLock.holdReadings; i++) {
      lock.feed(inTune: true, note: 'A');
    }
    expect(lock.isLocked, isTrue);
    lock.feed(inTune: false, note: 'A');
    expect(lock.isLocked, isFalse);
    var fired = 0;
    for (var i = 0; i < InTuneLock.holdReadings; i++) {
      if (lock.feed(inTune: true, note: 'A')) fired++;
    }
    expect(fired, 1, reason: 'can celebrate again after re-tuning');
  });

  test('moving to another string resets the hold', () {
    final lock = InTuneLock();
    for (var i = 0; i < InTuneLock.holdReadings - 1; i++) {
      lock.feed(inTune: true, note: 'A');
    }
    // Next string — the accumulated hold must not carry over.
    expect(lock.feed(inTune: true, note: 'D'), isFalse);
    expect(lock.isLocked, isFalse);
  });
}
