import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord_voicing.dart';

void main() {
  group('ChordVoicing.midiNotes', () {
    test('the C-shape open chord sounds C3-E3-G3-C4-E4', () {
      // [-1, 3, 2, 0, 1, 0] low-E -> high-E; low-E and the -1 mute the 6th
      // string, so 5 strings sound.
      const expected = [48, 52, 55, 60, 64];
      expect(ChordVoicing.midiNotes(const [-1, 3, 2, 0, 1, 0]), expected);
    });

    test('the E-shape open chord sounds every string (E-B-E-G#-B-E)', () {
      // [0, 2, 2, 1, 0, 0]: open low-E, A-string fret 2 (B), D-string fret 2
      // (E), G-string fret 1 (G#), open B, open high-E — the familiar open
      // E-major voicing, NOT the six open-string pitches.
      const expected = [40, 47, 52, 56, 59, 64];
      expect(ChordVoicing.midiNotes(const [0, 2, 2, 1, 0, 0]), expected);
    });

    test('an all-muted fingering sounds nothing', () {
      expect(ChordVoicing.midiNotes(const [-1, -1, -1, -1, -1, -1]), isEmpty);
    });

    test('a fret past the fingerboard (>24) is muted, not guessed', () {
      expect(ChordVoicing.midiNotes(const [30, -1, -1, -1, -1, -1]), isEmpty);
    });
  });

  group('ChordVoicing.frequencies', () {
    test('open low-E (E2) is ~82.41 Hz under concert pitch', () {
      final freqs = ChordVoicing.frequencies(const [0, -1, -1, -1, -1, -1]);
      expect(freqs, hasLength(1));
      expect(freqs.single, closeTo(82.41, 0.05));
    });

    test('a non-standard a4 scales every frequency', () {
      const frets = [0, -1, -1, -1, -1, -1];
      final freqs = ChordVoicing.frequencies(frets, a4: 432);
      expect(freqs, hasLength(1));
      expect(freqs.single, closeTo(80.91, 0.05));
    });
  });
}
