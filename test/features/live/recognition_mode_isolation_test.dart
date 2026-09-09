// E14-R30 (ADR 0544) — the expected-chord prior's STRICT isolation.
//
// Before this round the isolation was a calling convention: `live_screen.dart`
// called `setExpectedChord(null)` on entry and a comment said the prior "must
// never mask a genuinely different played chord". A convention is not a
// guarantee — nothing failed if a caller forgot, and the prior itself was an
// ADDITIVE trellis bias that could accumulate past the audio evidence.
//
// These cells pin the machine-checked replacement:
//   1. the type system refuses to build a hint in free mode;
//   2. a free-mode pipeline fed a deliberately WRONG expected chord emits
//      BIT-IDENTICAL frames to one that was never given a hint at all;
//   3. free mode never reports a tie-break, whatever a caller pushes in.
// The tie-break's own semantics are pinned in dsp/viterbi_decoder_test.dart.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_mode.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/model/beat_slot.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

import '../../support/synth.dart';

const _sr = 44100;

List<LiveFrame> _drive(
  LivePipeline pipe,
  Float64List signal, {
  int chunk = 2048,
  void Function(int chunkIndex)? beforeChunk,
}) {
  final frames = <LiveFrame>[];
  var index = 0;
  for (var i = 0; i < signal.length; i += chunk) {
    beforeChunk?.call(index++);
    final end = (i + chunk < signal.length) ? i + chunk : signal.length;
    frames.addAll(pipe.addChunk(signal.sublist(i, end)));
  }
  return frames;
}

/// Everything a [LiveFrame] carries, flattened to primitives — an equality on
/// this list IS bit-identity of the emitted stream.
List<Object?> _signature(LiveFrame f) => <Object?>[
  f.current?.label,
  f.next?.label,
  f.latestStrum?.direction,
  f.latestStrum?.confidence,
  f.bpm,
  f.inputLevel,
  f.tuningHz,
  f.listening,
  f.strumSeq,
  f.latestStrumTime,
  f.onsetTimeSec,
  f.engineTimeSec,
  f.chordDecision,
  f.chordRejectReason,
  for (final BeatSlot s in f.bar) ...[
    s.label,
    s.isDownbeat,
    s.strum?.direction,
    s.strum?.confidence,
  ],
];

void main() {
  group('ADR 0544 D2 — a free-mode hint cannot even be constructed', () {
    test('forMode(free, label) is null for every label', () {
      for (final label in ['C', 'Am', 'F#m7', 'G/B']) {
        expect(
          ExpectedChordHint.forMode(RecognitionMode.free, label),
          isNull,
          reason: 'free mode must have no hint VALUE to apply',
        );
      }
    });

    test('forMode(guided, label) yields the hint; a null/empty label does '
        'not', () {
      expect(
        ExpectedChordHint.forMode(RecognitionMode.guided, 'Am')?.label,
        'Am',
      );
      expect(ExpectedChordHint.forMode(RecognitionMode.guided, null), isNull);
      expect(ExpectedChordHint.forMode(RecognitionMode.guided, ''), isNull);
    });

    test('the mode itself states the rule, exhaustively', () {
      expect(RecognitionMode.free.allowsExpectedChordPrior, isFalse);
      expect(RecognitionMode.guided.allowsExpectedChordPrior, isTrue);
    });

    test('a pipeline defaults to free — fail-closed', () {
      expect(LivePipeline(sampleRate: _sr).mode, RecognitionMode.free);
    });
  });

  group('ADR 0544 D2 — free-mode bit-identity guard', () {
    // A C-major chord played as Karplus–Strong strings, while the "lesson"
    // insists the player is on G. Under the old additive prior this input is
    // exactly the one that could drift; in free mode it must be inert.
    Float64List signal() => karplusStrongStrumPattern(
      cMajorFreqs,
      count: 3,
      gapSeconds: 0.6,
      sampleRate: _sr,
    );

    test('a WRONG expected chord set up front changes nothing', () {
      final withHint = LivePipeline(sampleRate: _sr)..setExpectedChord('G');
      final without = LivePipeline(sampleRate: _sr);

      final a = _drive(withHint, signal());
      final b = _drive(without, signal());

      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(_signature(a[i]), _signature(b[i]), reason: 'frame $i');
      }
    });

    test('a hint pushed in REPEATEDLY, mid-stream, still changes nothing', () {
      // The realistic leak: a lesson controller re-asserting its target on
      // every beat while the user is actually in Free Play.
      const targets = ['G', 'Am', 'F', 'Cmaj7'];
      final withHint = LivePipeline(sampleRate: _sr);
      final without = LivePipeline(sampleRate: _sr);

      final a = _drive(
        withHint,
        signal(),
        beforeChunk: (i) =>
            withHint.setExpectedChord(targets[i % targets.length]),
      );
      final b = _drive(without, signal());

      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(_signature(a[i]), _signature(b[i]), reason: 'frame $i');
      }
    });

    test('free mode never reports an expected-chord tie-break', () {
      final pipe = LivePipeline(sampleRate: _sr)..setExpectedChord('G');
      final pcm = signal();
      final seen = <bool>[];
      var lastIndex = -1;
      for (var i = 0; i < pcm.length; i += 1024) {
        final end = (i + 1024 < pcm.length) ? i + 1024 : pcm.length;
        pipe.addChunk(pcm.sublist(i, end));
        final d = pipe.chordLatchDiagnostics;
        if (d != null && d.frameIndex != lastIndex) {
          lastIndex = d.frameIndex;
          seen.add(d.expectedTieBreakApplied);
        }
      }
      expect(seen, isNotEmpty, reason: 'the harness must have observed frames');
      expect(seen.every((applied) => !applied), isTrue);
    });
  });

  group('ADR 0544 D1 — the mode is carried, not guessed', () {
    test('a guided pipeline reports guided, and its diagnostics say so', () {
      final pipe = LivePipeline(sampleRate: _sr, mode: RecognitionMode.guided)
        ..setExpectedChord('C');
      expect(pipe.mode, RecognitionMode.guided);
      _drive(
        pipe,
        karplusStrongChord(cMajorFreqs, seconds: 1.2, sampleRate: _sr),
      );
      expect(pipe.chordLatchDiagnostics?.mode, RecognitionMode.guided);
    });
  });
}
