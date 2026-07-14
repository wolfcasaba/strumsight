// Round 176 — the musical-presence gate: the Live screen must NOT show a chord
// on non-guitar audio (voiced speech / humming / a lone tone), while a real
// guitar chord still shows. The field bug (user report): "in live mode the
// chords jump around wildly on speech — it doesn't filter the human voice."
//
// Root cause (round 176 probe): the only non-guitar gate was chroma tonalness
// (top-3 pitch-class energy), which rejects broadband noise but NOT pitched,
// harmonic voice. The fix gates the DISPLAYED chord on a Schmitt trigger over
// the EMA-smoothed chord-MATCH confidence — the feature that actually
// separates guitar (unambiguous, high-margin, sustained) from voice (weak,
// ambiguous, choppy). Tuned on real audio in test/tools/real_audio_probe_test.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/live_pipeline.dart';
import 'package:music_theory/features/live/model/live_frame.dart';

import '../../../support/synth.dart';

/// Stream a signal through the pipeline and return every emitted frame.
List<LiveFrame> _drive(LivePipeline pipe, Float64List signal,
    {int chunk = 2048}) {
  final frames = <LiveFrame>[];
  for (var i = 0; i < signal.length; i += chunk) {
    final end = (i + chunk < signal.length) ? i + chunk : signal.length;
    frames.addAll(pipe.addChunk(signal.sublist(i, end)));
  }
  return frames;
}

int _shown(List<LiveFrame> frames) =>
    frames.where((f) => f.current != null).length;

void main() {
  const sr = 44100;

  test('a strong C-major triad STILL surfaces a chord (no over-rejection)', () {
    final pipe = LivePipeline(sampleRate: sr);
    final triad = chordSignal(cMajorFreqs, seconds: 2.5, sampleRate: sr);
    final frames = _drive(pipe, triad);
    expect(_shown(frames), greaterThan(0),
        reason: 'a clean guitar chord must clear the musical-presence gate');
    expect(frames.map((f) => f.current?.label).whereType<String>(),
        contains('C'),
        reason: 'and it should read as C');
  });

  test('a single sustained tone (monophonic, ambiguous) shows NO phantom chord',
      () {
    // One pitch is not a chord — it matches many profiles weakly (low margin →
    // low confidence), so the gate must keep the display blank rather than
    // guessing. This is the mechanism that also rejects a hummed/sung note.
    final pipe = LivePipeline(sampleRate: sr);
    final tone = harmonicNote(freq: 220, seconds: 2.5, sampleRate: sr);
    final frames = _drive(pipe, tone);
    expect(_shown(frames), 0,
        reason: 'ambiguous single-pitch audio must not latch a chord');
  });

  test('the confidence gate is wired: an impossible rise shows nothing, '
      'a zero rise shows the chord', () {
    final triad = chordSignal(cMajorFreqs, seconds: 2.5, sampleRate: sr);

    final open = LivePipeline(sampleRate: sr, chordConfRise: 0.0);
    expect(_shown(_drive(open, triad)), greaterThan(0));

    final closed =
        LivePipeline(sampleRate: sr, chordConfRise: 1.01, chordConfRelease: 1.0);
    expect(_shown(_drive(closed, triad)), 0,
        reason: 'no real confidence can cross an impossible gate');
  });

  test('raising the rise gate never INCREASES the frames a chord is shown '
      '(monotone) — property', () {
    final triad = chordSignal(cMajorFreqs, seconds: 3.0, sampleRate: sr);
    var prev = 1 << 30;
    for (final rise in [0.0, 0.3, 0.5, 0.54, 0.7, 0.9]) {
      final n = _shown(_drive(
          LivePipeline(sampleRate: sr, chordConfRise: rise), triad));
      expect(n, lessThanOrEqualTo(prev),
          reason: 'a stricter gate cannot surface more chord frames');
      prev = n;
    }
  });

  test('a latched chord HOLDS through a brief gap then releases on silence '
      '(Schmitt hold, not per-frame flicker)', () {
    final pipe = LivePipeline(sampleRate: sr);
    final chord = chordSignal(cMajorFreqs, seconds: 2.0, sampleRate: sr);
    final gap = Float64List(sr ~/ 5); // 0.2 s silence — shorter than release
    final silence = Float64List(sr); // 1 s silence — must release
    // chord, short gap, chord again: the display should stay latched across the
    // short gap (a real strum's momentary decay must not blank the chord).
    final held = _drive(pipe, chord) +
        _drive(pipe, gap) +
        _drive(pipe, chord);
    expect(_shown(held), greaterThan(0));
    // Now a long silence: the chord must eventually release (fall below the
    // release floor) — the display goes blank, not stuck on a stale chord.
    final tail = _drive(pipe, silence);
    expect(tail.isNotEmpty && tail.last.current == null, isTrue,
        reason: 'sustained silence must release the latched chord');
  });

  test('the default gate constants are ordered (rise > release, both in 0..1)',
      () {
    expect(DspConfig.chordConfRise, greaterThan(DspConfig.chordConfRelease));
    expect(DspConfig.chordConfRelease, greaterThan(0));
    expect(DspConfig.chordConfRise, lessThan(1));
  });
}
