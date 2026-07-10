import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/clip_analyzer.dart';

import '../../support/synth.dart';

/// Chunk 012's last stage — full-sequence (batch) Viterbi with backtrace for
/// Analyze. The ONLINE decoder commits as it goes; measured on a fast
/// 4-chord clip (0.8 s per chord) it emitted 7 segments including 0.1 s
/// transients (Am7, Fsus4) and ended on a WRONG final label (Csus4 instead
/// of F). The globally optimal path has none of that.
void main() {
  const analyzer = ClipAnalyzer();

  test('fast 4-chord clip yields exactly C G Am F (no transient junk)', () {
    final pcm = [
      ...chordSignal(cMajorFreqs, seconds: 0.8),
      ...chordSignal(gMajorFreqs, seconds: 0.8),
      ...chordSignal(aMinorFreqs, seconds: 0.8),
      ...chordSignal(fMajorFreqs, seconds: 0.8),
    ];
    final result = analyzer.analyze(pcm, 44100);

    expect([for (final c in result.chords) c.label], ['C', 'G', 'Am', 'F']);
  });

  test('4-chord boundaries land near the true change points', () {
    final pcm = [
      ...chordSignal(cMajorFreqs, seconds: 0.8),
      ...chordSignal(gMajorFreqs, seconds: 0.8),
      ...chordSignal(aMinorFreqs, seconds: 0.8),
      ...chordSignal(fMajorFreqs, seconds: 0.8),
    ];
    final result = analyzer.analyze(pcm, 44100);
    expect(result.chords.length, 4);
    expect(result.chords[1].startSec, closeTo(0.8, 0.3));
    expect(result.chords[2].startSec, closeTo(1.6, 0.3));
    expect(result.chords[3].startSec, closeTo(2.4, 0.3));
    // Segments tile the clip: contiguous, and the last ends at the clip end.
    for (var i = 1; i < result.chords.length; i++) {
      expect(result.chords[i].startSec, result.chords[i - 1].endSec);
    }
    expect(result.chords.last.endSec, closeTo(result.durationSec, 0.01));
  });

  test('two-chord clip still yields exactly C then G (regression)', () {
    final pcm = [
      ...chordSignal(cMajorFreqs, seconds: 1.5),
      ...chordSignal(gMajorFreqs, seconds: 1.5),
    ];
    final result = analyzer.analyze(pcm, 44100);
    expect([for (final c in result.chords) c.label], ['C', 'G']);
  });

  test('ring-out transition (chords overlap) stays clean C then G', () {
    final c = chordSignal(cMajorFreqs, seconds: 2.2, decayPerSecond: 0.8);
    final g = chordSignal(gMajorFreqs, seconds: 2.2, decayPerSecond: 0.8);
    final mixed = mixNotes([c, g], startOffsets: [0, (1.5 * 44100).round()]);
    final result = analyzer.analyze(mixed.toList(), 44100);
    expect([for (final ch in result.chords) ch.label], ['C', 'G']);
  });
}
