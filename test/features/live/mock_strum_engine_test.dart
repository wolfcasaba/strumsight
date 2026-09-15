import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/mock_strum_engine.dart';
import 'package:strumsight/core/music/strum.dart';

void main() {
  final engine = MockStrumEngine(bpm: 96); // one bar = 2.5 s

  test('frameAt(0) starts on the first chord of the progression', () {
    final f = engine.frameAt(Duration.zero);
    expect(f.current!.label, 'C');
    expect(f.next!.label, 'G');
    expect(f.listening, isTrue);
    expect(f.tuningHz, 440);
  });

  test('progression advances by bar', () {
    expect(
      engine.frameAt(const Duration(milliseconds: 2600)).current!.label,
      'G',
    );
    expect(
      engine.frameAt(const Duration(milliseconds: 5200)).current!.label,
      'Am',
    );
    expect(
      engine.frameAt(const Duration(milliseconds: 7700)).current!.label,
      'F',
    );
    expect(
      engine.frameAt(const Duration(milliseconds: 10200)).current!.label,
      'C',
    );
  });

  test('bar always has 8 labelled slots in the standard order', () {
    final f = engine.frameAt(const Duration(milliseconds: 1000));
    expect(f.bar.length, 8);
    expect(f.bar.map((b) => b.label).toList(), [
      '1',
      '&',
      '2',
      '&',
      '3',
      '&',
      '4',
      '&',
    ]);
    // Numbered beats are down-beats; "&" are off-beats.
    expect(f.bar[0].isDownbeat, isTrue);
    expect(f.bar[1].isDownbeat, isFalse);
  });

  test('all confidences and input level stay within 0..1', () {
    for (var ms = 0; ms < 12000; ms += 25) {
      final f = engine.frameAt(Duration(milliseconds: ms));
      expect(f.inputLevel, inInclusiveRange(0.0, 1.0));
      for (final slot in f.bar) {
        final s = slot.strum;
        if (s != null) {
          expect(s.confidence, inInclusiveRange(0.0, 1.0));
        }
      }
    }
  });

  test('up-strokes are modelled as less confident than down-strokes', () {
    final f = engine.frameAt(const Duration(milliseconds: 1000));
    final downs = f.bar
        .where((b) => b.strum?.isDown ?? false)
        .map((b) => b.strum!.confidence);
    final ups = f.bar
        .where((b) => b.strum?.isUp ?? false)
        .map((b) => b.strum!.confidence);
    final avgDown = downs.reduce((a, b) => a + b) / downs.length;
    final avgUp = ups.reduce((a, b) => a + b) / ups.length;
    expect(avgUp, lessThan(avgDown));
  });

  test('latestStrum is a downstroke right after the first downbeat', () {
    final f = engine.frameAt(const Duration(milliseconds: 300));
    expect(f.latestStrum, isNotNull);
    expect(f.latestStrum!.direction, StrumDirection.down);
    expect(f.latestStrum!.accent, isTrue); // beat 1 is accented
  });

  group('onsetSeq leads strumSeq by the classification delay', () {
    // One bar = 2.5 s at 96 BPM, so the eighth-note slots start at 0, 312.5,
    // 625, … ms; the pattern's strums are slots 0, 2, 3, 5, 6 and 7.
    const delay = MockStrumEngine.directionDelay;

    test('the very first hit is HEARD before it is classified', () {
      final onset = engine.frameAt(Duration.zero);
      expect(onset.onsetSeq, 1, reason: 'the strike is confirmed at once');
      expect(onset.strumSeq, 0, reason: 'the direction is not known yet');

      final justBefore = engine.frameAt(
        delay - const Duration(microseconds: 1),
      );
      expect(justBefore.onsetSeq, 1);
      expect(justBefore.strumSeq, 0);

      final verdict = engine.frameAt(delay);
      expect(verdict.onsetSeq, 1);
      expect(verdict.strumSeq, 1, reason: 'the verdict lands one delay later');
    });

    test('every later strum repeats the same two-stage bump', () {
      // Slot 2 of bar 0 strikes at 625 ms.
      const strike = Duration(milliseconds: 625);
      expect(engine.frameAt(strike).onsetSeq, 2);
      expect(engine.frameAt(strike).strumSeq, 1);
      expect(engine.frameAt(strike + delay).strumSeq, 2);
    });

    test('both counters are monotonic and onsetSeq never trails strumSeq', () {
      var lastOnset = 0;
      var lastStrum = 0;
      for (var ms = 0; ms < 12000; ms += 5) {
        final f = engine.frameAt(Duration(milliseconds: ms));
        expect(f.onsetSeq, greaterThanOrEqualTo(lastOnset));
        expect(f.strumSeq, greaterThanOrEqualTo(lastStrum));
        expect(f.onsetSeq, greaterThanOrEqualTo(f.strumSeq));
        // At most one strum can be awaiting its verdict: the pattern's
        // tightest gap (312.5 ms) is far wider than the 70 ms delay.
        expect(f.onsetSeq - f.strumSeq, lessThanOrEqualTo(1));
        lastOnset = f.onsetSeq;
        lastStrum = f.strumSeq;
      }
    });

    test('a full bar contributes exactly its six pattern strums', () {
      expect(engine.frameAt(const Duration(milliseconds: 2499)).onsetSeq, 6);
      // The next bar's downbeat, counted the instant it lands.
      expect(engine.frameAt(const Duration(milliseconds: 2500)).onsetSeq, 7);
    });

    test('at the default tick the first emitted frame is onset-only', () {
      final e = MockStrumEngine(bpm: 96);
      final first = e.frameAt(e.tickInterval);
      expect(e.tickInterval, lessThan(MockStrumEngine.directionDelay));
      expect(first.onsetSeq, 1);
      expect(first.strumSeq, 0);
    });
  });

  test('frames stream emits a well-formed frame after start()', () async {
    final e = MockStrumEngine(tickInterval: const Duration(milliseconds: 10));
    await e.start();
    final frame = await e.frames.first;
    expect(frame.bar.length, 8);
    expect(frame.current, isNotNull);
    await e.dispose();
  });
}
