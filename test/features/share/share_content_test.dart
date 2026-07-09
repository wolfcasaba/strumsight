import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/share/share_content.dart';

AnalyzeResult _result({double bpm = 96}) => AnalyzeResult(
      durationSec: 12,
      bpm: bpm,
      chords: const [
        TimelineChord(label: 'C', startSec: 0, endSec: 3),
        TimelineChord(label: 'G', startSec: 3, endSec: 6),
        TimelineChord(label: 'Am', startSec: 6, endSec: 9),
      ],
      strums: [
        for (var i = 0; i < 5; i++)
          TimelineStrum(
            direction: i.isEven ? StrumDirection.down : StrumDirection.up,
            timeSec: i.toDouble(),
            confidence: 0.9,
          ),
      ],
    );

void main() {
  test('caption carries the chords, the ↓/↑ moat stats, and the BPM', () {
    final c = ShareContent.caption(_result());
    expect(c, contains('C · G · Am'));
    expect(c, contains('3 down')); // 5 strums → 3 down, 2 up
    expect(c, contains('2 up'));
    expect(c, contains('96 BPM'));
  });

  test('caption carries attribution, install link and the UGC hashtag', () {
    final c = ShareContent.caption(_result());
    expect(c, contains('StrumSight'));
    expect(c, contains(ShareContent.installUrl));
    expect(c, contains('#StrumSightChallenge'));
  });

  test('chords are capo-shifted like the rest of the app', () {
    // Capo 2 ⇒ the fretted shape is 2 semitones below concert pitch.
    expect(ShareContent.chords(_result(), capo: 2), 'A# · F · Gm');
  });

  test('strumGlyphs renders the actual ↓/↑ sequence', () {
    expect(ShareContent.strumGlyphs(_result()), '↓ ↑ ↓ ↑ ↓');
  });

  test('strumGlyphs caps long patterns with an ellipsis', () {
    final many = AnalyzeResult(
      durationSec: 30,
      bpm: 120,
      chords: const [],
      strums: [
        for (var i = 0; i < 40; i++)
          TimelineStrum(
              direction: StrumDirection.down, timeSec: i.toDouble(), confidence: 1),
      ],
    );
    final g = ShareContent.strumGlyphs(many, max: 16);
    expect('↓'.allMatches(g).length, 16);
    expect(g, endsWith('…'));
  });

  test('an empty result still yields a safe, shareable caption', () {
    final c = ShareContent.caption(AnalyzeResult.empty);
    expect(c, contains('My riff'));
    expect(c, isNot(contains('BPM'))); // no tempo when none detected
    expect(c, contains(ShareContent.installUrl));
  });

  test('bpm=0 omits the tempo but keeps the strokes line', () {
    final c = ShareContent.caption(_result(bpm: 0));
    expect(c, isNot(contains('BPM')));
    expect(c, contains('down'));
  });
}
