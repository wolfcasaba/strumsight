import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/audio/chord_audio.dart';

String _tag(List<int> b, int o) => String.fromCharCodes(b.sublist(o, o + 4));

void main() {
  group('ChordAudio.frequencies', () {
    test('parses a major triad into three chord tones', () {
      final f = ChordAudio.frequencies('C');
      expect(f, isNotNull);
      expect(f!.length, 3);
      expect(f[0], closeTo(130.81, 0.5)); // C3
      expect(f[1], closeTo(164.81, 0.5)); // E3
      expect(f[2], closeTo(196.0, 0.5)); // G3
    });

    test('uses the minor third for minor chords', () {
      final maj = ChordAudio.frequencies('A')!;
      final min = ChordAudio.frequencies('Am')!;
      // The third differs (A major = C#, A minor = C natural, lower).
      expect(min[1], lessThan(maj[1]));
    });

    test('sevenths add a fourth tone; unknown labels return null', () {
      expect(ChordAudio.frequencies('G7')!.length, 4);
      expect(ChordAudio.frequencies('Zz9'), isNull);
      expect(ChordAudio.frequencies(''), isNull);
    });

    test('7sus4 keeps the suspended fourth, not a major third (round 90)',
        () {
      // A7sus4 is in the library; before round 90 it fell back to a plain
      // major triad. The 2nd tone must be the FOURTH (5 semitones up).
      final f = ChordAudio.frequencies('A7sus4')!;
      expect(f.length, 4);
      final root = f[0];
      expect(f[1] / root, closeTo(1.3348, 0.002)); // 2^(5/12)
      expect(f[3] / root, closeTo(1.7818, 0.002)); // 2^(10/12), the b7
    });
  });

  test('padWav produces a well-formed, non-silent WAV', () {
    final wav = ChordAudio.padWav(ChordAudio.frequencies('C')!, ms: 200);
    expect(_tag(wav, 0), 'RIFF');
    expect(_tag(wav, 8), 'WAVE');
    expect(_tag(wav, 36), 'data');
    expect(wav.sublist(44).any((b) => b != 0), isTrue);
  });
}
