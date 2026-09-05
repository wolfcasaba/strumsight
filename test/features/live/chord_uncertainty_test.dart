import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:strumsight/features/live/model/beat_slot.dart';
import 'package:strumsight/core/music/strum.dart';
// Everything reachable via the public barrel is imported from there — never
// the direct domain file (ADR 0505 §0.0 R4 pattern, same as
// strum_direction_abstention_test.dart). `LivePipeline` and
// `StrumDirectionClassifier` stay direct imports: the DSP/ML engine is
// deliberately NOT exported (public.dart's own NOTE), and every other
// pipeline test in this tree reaches them the same way.
import 'package:strumsight/features/live/public.dart';

import '../../support/synth.dart';

const _sr = 44100;

RecognitionRuntimeInfo _runtimeInfo() => const RecognitionRuntimeInfo(
  strumModelId: 'none',
  strumModelVersion: 0,
  strumModelSha256: '',
  chordEngineId: RecognitionRuntimeInfo.chordEngineNnlsViterbi,
  sampleRate: _sr,
  frontendVersion: RecognitionRuntimeInfo.frontendCrnnV1,
);

/// Feeds [signal] in mic-like ~23 ms chunks and returns every emitted frame —
/// same pattern as `test/features/live/dsp/live_pipeline_test.dart`.
List<LiveFrame> _run(
  LivePipeline pipeline,
  List<double> signal, {
  int chunkSize = 1024,
}) {
  final frames = <LiveFrame>[];
  for (var i = 0; i < signal.length; i += chunkSize) {
    final end = (i + chunkSize < signal.length) ? i + chunkSize : signal.length;
    frames.addAll(pipeline.addChunk(signal.sublist(i, end)));
  }
  return frames;
}

/// A [StrumDirectionClassifier] returning a FIXED verdict regardless of audio
/// content — same pattern as `strum_direction_abstention_test.dart`'s
/// `_FixedClassifier`, used here to guarantee a HIGH, deterministic strum
/// confidence for the §6 pt.6 "chord ≠ strum source" cell.
class _FixedClassifier implements StrumDirectionClassifier {
  _FixedClassifier(this.verdict);
  final StrumClassification verdict;

  @override
  void observe(Float64List frame, StrumFrameFeatures features) {}

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) => verdict;
}

void main() {
  group(
    'E14-R11: the pipeline produces a typed chord verdict (ADR 0516 D1, §6 pt.1)',
    () {
      test('a sustained, tonal chord confirms with the merged '
          'RecognitionDecision', () {
        final pipeline = LivePipeline(sampleRate: _sr);
        final frames = _run(pipeline, chordSignal(cMajorFreqs, seconds: 1.5));
        expect(frames, isNotEmpty);
        expect(frames.last.current?.label, 'C');
        final prediction = pipeline.chordPrediction;
        expect(prediction, isNotNull);
        expect(prediction!.decision, RecognitionDecision.confirmed);
      });
    },
  );

  group('E14-R11: decision == confirmed exactly when showChord (§6 pt.2)', () {
    test('confirmed cell: the frame shows a chord -> decision confirmed', () {
      final pipeline = LivePipeline(sampleRate: _sr);
      final frames = _run(pipeline, chordSignal(cMajorFreqs, seconds: 1.5));
      expect(frames.last.current, isNotNull);
      expect(pipeline.chordPrediction!.decision, RecognitionDecision.confirmed);
    });

    test(
      'inverse cell: the frame shows no chord -> decision never confirmed',
      () {
        final pipeline = LivePipeline(sampleRate: _sr);
        final frames = _run(pipeline, Float64List(_sr)); // 1 s of silence
        expect(frames.last.current, isNull);
        expect(
          pipeline.chordPrediction!.decision,
          isNot(RecognitionDecision.confirmed),
        );
      },
    );
  });

  group('E14-R11: the four §5.4 mapping rows (ADR 0516 D4)', () {
    test('confirmed: the kapu latched and a match exists, '
        'regardless of signal quality', () {
      final (decision, reason) = LivePipeline.debugDeriveChordDecision(
        chordLatched: true,
        hasMatch: true,
        signalQualityState: SignalQualityState.good,
      );
      expect(decision, RecognitionDecision.confirmed);
      expect(reason, isNull);
    });

    test('signalQuality: a bad mic reading rejects, never blamed as '
        'lowConfidence', () {
      final (decision, reason) = LivePipeline.debugDeriveChordDecision(
        chordLatched: false,
        hasMatch: true,
        signalQualityState: SignalQualityState.tooLoud,
      );
      expect(decision, RecognitionDecision.rejected);
      expect(reason, RecognitionRejectReason.signalQuality);
    });

    test('noChord: tonalness-gated / no match, signal quality good', () {
      final (decision, reason) = LivePipeline.debugDeriveChordDecision(
        chordLatched: false,
        hasMatch: false,
        signalQualityState: SignalQualityState.good,
      );
      expect(decision, RecognitionDecision.rejected);
      expect(reason, RecognitionRejectReason.noChord);
    });

    test('lowConfidence: a match exists but under the gate', () {
      final (decision, reason) = LivePipeline.debugDeriveChordDecision(
        chordLatched: false,
        hasMatch: true,
        signalQualityState: SignalQualityState.good,
      );
      expect(decision, RecognitionDecision.uncertain);
      expect(reason, RecognitionRejectReason.lowConfidence);
    });
  });

  group(
    'E14-R11: rise-gate inclusivity at the EXACT EMA boundary (§6 pt.4)',
    () {
      test(
        'EMA 0.53 (below the threshold) -> not latched -> not confirmed',
        () {
          final pipeline = LivePipeline(sampleRate: _sr);
          pipeline.debugApplyChordConfEma(0.53);
          expect(pipeline.debugChordLatched, isFalse);
          final (decision, _) = LivePipeline.debugDeriveChordDecision(
            chordLatched: pipeline.debugChordLatched,
            hasMatch: true,
            signalQualityState: SignalQualityState.good,
          );
          expect(decision, isNot(RecognitionDecision.confirmed));
        },
      );

      test('EMA 0.54 (exactly on it) -> latched -> confirmed '
          '(the boundary is inclusive)', () {
        final pipeline = LivePipeline(sampleRate: _sr);
        pipeline.debugApplyChordConfEma(0.54);
        expect(pipeline.debugChordLatched, isTrue);
        final (decision, _) = LivePipeline.debugDeriveChordDecision(
          chordLatched: pipeline.debugChordLatched,
          hasMatch: true,
          signalQualityState: SignalQualityState.good,
        );
        expect(decision, RecognitionDecision.confirmed);
      });

      test('EMA 0.55 (above the threshold) -> latched -> confirmed', () {
        final pipeline = LivePipeline(sampleRate: _sr);
        pipeline.debugApplyChordConfEma(0.55);
        expect(pipeline.debugChordLatched, isTrue);
        final (decision, _) = LivePipeline.debugDeriveChordDecision(
          chordLatched: pipeline.debugChordLatched,
          hasMatch: true,
          signalQualityState: SignalQualityState.good,
        );
        expect(decision, RecognitionDecision.confirmed);
      });
    },
  );

  group('E14-R11: calibratedConfidence stays null (ADR 0505 D2, ADR 0516 D2, '
      '§6 pt.5)', () {
    test(
      'a confirmed prediction still carries a null calibratedConfidence',
      () {
        final pipeline = LivePipeline(sampleRate: _sr);
        _run(pipeline, chordSignal(cMajorFreqs, seconds: 1.5));
        expect(pipeline.chordPrediction!.calibratedConfidence, isNull);
      },
    );

    test('a rejected/no-match prediction also carries a null '
        'calibratedConfidence', () {
      final pipeline = LivePipeline(sampleRate: _sr);
      _run(pipeline, Float64List(_sr));
      expect(pipeline.chordPrediction!.calibratedConfidence, isNull);
    });
  });

  group('E14-R11: chord and strum confidence come from different sources '
      '(§6 pt.6)', () {
    test('high strum confidence while the chord stays NOT confirmed', () {
      final pipeline = LivePipeline.debugWithClassifier(
        _FixedClassifier(
          const StrumClassification(
            direction: StrumDirection.down,
            confidence: 0.95,
          ),
        ),
        sampleRate: _sr,
      );
      final frames = _run(pipeline, strumSignal(lowFirst: true));
      final withArrow = frames.where((f) => f.latestStrum != null).toList();
      expect(withArrow, isNotEmpty);
      expect(withArrow.first.confidence, greaterThan(0.9));
      expect(
        pipeline.chordPrediction!.decision,
        isNot(RecognitionDecision.confirmed),
        reason:
            'a single mixed-open-string strum must not accidentally match '
            'a dictionary chord profile',
      );
    });

    test('chord confirmed while the strum confidence stays at its '
        '"nothing detected" floor', () {
      final pipeline = LivePipeline(sampleRate: _sr);
      final frames = _run(pipeline, chordSignal(cMajorFreqs, seconds: 1.5));
      expect(pipeline.chordPrediction!.decision, RecognitionDecision.confirmed);
      expect(
        frames.last.confidence,
        lessThan(0.5),
        reason:
            'a sustained chord tone has no percussive attack for the '
            'onset detector to latch a strum onto',
      );
    });
  });

  group('E14-R11: LiveFrame compatibility (§6 pt.7)', () {
    test('LiveFrame.empty has null chord fields', () {
      expect(LiveFrame.empty.chordDecision, isNull);
      expect(LiveFrame.empty.chordRejectReason, isNull);
    });

    test('copyWith preserves the new fields', () {
      const frame = LiveFrame(
        current: null,
        next: null,
        latestStrum: null,
        bar: <BeatSlot>[],
        bpm: 0,
        inputLevel: 0,
        tuningHz: 440,
        listening: false,
        chordDecision: RecognitionDecision.uncertain,
        chordRejectReason: RecognitionRejectReason.lowConfidence,
      );
      final copy = frame.copyWith(bpm: 120);
      expect(copy.chordDecision, RecognitionDecision.uncertain);
      expect(copy.chordRejectReason, RecognitionRejectReason.lowConfidence);
    });
  });

  group(
    'E14-R11: the adapter gap is pinned, not silent (ADR 0516 D7, §6 pt.8)',
    () {
      test(
        'LiveFrameAdapter.toLiveFrame leaves chordDecision null even when the '
        'RecognitionFrame carries a confirmed chord',
        () {
          final chord = ChordPrediction(
            label: 'Am',
            root: 'A',
            quality: 'min',
            pNoChord: 0.0,
            pUnknown: 0.0,
            calibratedConfidence: null,
            stabilityFrames: 6,
            sourceEngine: RecognitionRuntimeInfo.chordEngineNnlsViterbi,
            decision: RecognitionDecision.confirmed,
            rejectReason: null,
          );
          final frame = RecognitionFrame(
            frameTimeSec: 1.0,
            runtimeInfo: _runtimeInfo(),
            chord: chord,
          );
          const base = LiveFrame(
            current: null,
            next: null,
            latestStrum: null,
            bar: <BeatSlot>[],
            bpm: 0,
            inputLevel: 0,
            tuningHz: 440,
            listening: true,
          );
          final result = LiveFrameAdapter.toLiveFrame(frame, base);
          expect(
            result.current?.label,
            'Am',
            reason: 'the legacy adapter DOES show the confirmed chord today',
          );
          expect(
            result.chordDecision,
            isNull,
            reason:
                'the adapter is untouched this round (D7) — the typed field '
                'stays null even though a confirmed chord exists upstream',
          );
        },
      );
    },
  );
}
