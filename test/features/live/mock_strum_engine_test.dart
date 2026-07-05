import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/mock_strum_engine.dart';
import 'package:music_theory/features/live/model/strum.dart';

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
    expect(engine.frameAt(const Duration(milliseconds: 2600)).current!.label, 'G');
    expect(engine.frameAt(const Duration(milliseconds: 5200)).current!.label, 'Am');
    expect(engine.frameAt(const Duration(milliseconds: 7700)).current!.label, 'F');
    expect(engine.frameAt(const Duration(milliseconds: 10200)).current!.label, 'C');
  });

  test('bar always has 8 labelled slots in the standard order', () {
    final f = engine.frameAt(const Duration(milliseconds: 1000));
    expect(f.bar.length, 8);
    expect(
      f.bar.map((b) => b.label).toList(),
      ['1', '&', '2', '&', '3', '&', '4', '&'],
    );
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
    final downs =
        f.bar.where((b) => b.strum?.isDown ?? false).map((b) => b.strum!.confidence);
    final ups =
        f.bar.where((b) => b.strum?.isUp ?? false).map((b) => b.strum!.confidence);
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

  test('frames stream emits a well-formed frame after start()', () async {
    final e = MockStrumEngine(tickInterval: const Duration(milliseconds: 10));
    await e.start();
    final frame = await e.frames.first;
    expect(frame.bar.length, 8);
    expect(frame.current, isNotNull);
    await e.dispose();
  });
}
