// E14-R23 + E14-R26 — the shadow session driver.
//
// RED before this round: `runRecognitionShadow`, the observers and the
// recorder did not exist. What these cells PIN (SDD Ch14 Kör 23 acceptance):
//   1. gates closed  → ZERO work: no candidate call at all, and the snapshot
//      says so instead of reporting an empty-but-ran report;
//   2. the shadow output NEVER reaches a LiveFrame — the emitted stream with
//      the observers installed is bit-identical to the stream without them;
//   3. the disagreement report is DETERMINISTIC for the same PCM;
//   4. the sample ring stays bounded on a long stream.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/recognition_rollout_stage.dart';
import 'package:strumsight/features/live/data/shadow/chord_shadow_candidate.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_gate.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_observers.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_recorder.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_session.dart';
import 'package:strumsight/features/live/data/shadow/shadow_metrics.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_mode.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/model/beat_slot.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

import '../../../support/synth.dart';

const _sr = 44100;

/// A candidate that answers with a fixed label and COUNTS how often it was
/// asked. The counter is the machine guard for "flag OFF ⇒ zero inference":
/// a shadow path that is truly off never even asks.
class _CountingCandidate implements ChordShadowCandidateSource {
  _CountingCandidate({this.label = 'C', this.answerFrom = 0.0});

  final String label;
  final double answerFrom;
  int calls = 0;

  @override
  ChordShadowVerdict? verdictAtSeconds(double timeSec) {
    calls++;
    if (timeSec < answerFrom) return null;
    return ChordShadowVerdict(
      timeSec: timeSec,
      label: label,
      posterior: 0.9,
    );
  }
}

Float64List _signal() =>
    karplusStrongStrumPattern(cMajorFreqs, count: 3, sampleRate: _sr);

List<LiveFrame> _drive(LivePipeline pipe, Float64List signal) {
  const chunk = 2048;
  final out = <LiveFrame>[];
  for (var i = 0; i < signal.length; i += chunk) {
    final end = i + chunk < signal.length ? i + chunk : signal.length;
    out.addAll(pipe.addChunk(signal.sublist(i, end)));
  }
  return out;
}

List<Object?> _signature(LiveFrame f) => <Object?>[
  f.current?.label,
  f.next?.label,
  f.latestStrum?.direction,
  f.latestStrum?.confidence,
  f.bpm,
  f.inputLevel,
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
  ],
];

const _openGate = RecognitionShadowGate(
  strumEnabled: true,
  chordEnabled: false,
  strumStage: RecognitionRolloutStage.shadow,
  chordStage: RecognitionRolloutStage.off,
);

void main() {
  group('the gate decides whether ANY work happens', () {
    test('both gates closed → the disabled snapshot, no pipeline run', () {
      final snapshot = runRecognitionShadow(
        RecognitionShadowRequest(
          pcm: _signal(),
          sampleRate: _sr,
          gate: RecognitionShadowGate.closed,
        ),
      );
      expect(snapshot.ranAnything, isFalse);
      expect(snapshot.strum.observedFrames, 0);
      expect(snapshot.chord.observedFrames, 0);
      expect(snapshot.strumSamples, isEmpty);
      expect(snapshot.chordFallbackReason, isNull);
      expect(snapshot.strumStage, RecognitionRolloutStage.off);
    });

    test('a closed gate does not even PARSE the weights it was handed', () {
      // Deliberately corrupt bytes: if the closed gate still tried to bring
      // the chord model up, this would come back as a parseFailed fallback.
      // A null reason therefore proves nothing was attempted — a stronger
      // claim than "an inference ran and its result was dropped".
      final snapshot = runRecognitionShadow(
        RecognitionShadowRequest(
          pcm: _signal(),
          sampleRate: _sr,
          gate: RecognitionShadowGate.closed,
          chordWeights: Uint8List.fromList(List<int>.filled(64, 0xAB)),
        ),
      );
      expect(snapshot.chordFallbackReason, isNull);
      expect(snapshot.chord.observedFrames, 0);
      expect(snapshot.chordShadowEnabled, isFalse);
    });

    test('an OPEN chord gate does call it, once per emitted frame', () {
      final candidate = _CountingCandidate();
      final recorder = RecognitionShadowRecorder();
      final pipe = LivePipeline(
        sampleRate: _sr,
        shadowObserver: CompositeRecognitionShadowObserver([
          ChordShadowObserver(recorder: recorder, candidate: candidate),
        ]),
      );
      final frames = _drive(pipe, _signal());
      expect(frames, isNotEmpty);
      expect(candidate.calls, frames.length);
      expect(recorder.chordAggregate.observedFrames, frames.length);
    });
  });

  group('the shadow output can never reach production', () {
    test('installing BOTH observers leaves the frames bit-identical', () {
      final recorder = RecognitionShadowRecorder();
      final observed = LivePipeline(
        sampleRate: _sr,
        shadowObserver: CompositeRecognitionShadowObserver([
          StrumShadowObserver(recorder),
          ChordShadowObserver(
            recorder: recorder,
            candidate: _CountingCandidate(label: 'F#m'),
          ),
        ]),
      );
      final plain = LivePipeline(sampleRate: _sr);

      final a = _drive(observed, _signal());
      final b = _drive(plain, _signal());

      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(_signature(a[i]), _signature(b[i]), reason: 'frame $i');
      }
      // …and the shadow really did record something, so the comparison above
      // is not vacuously true.
      expect(recorder.chordAggregate.comparedFrames, greaterThan(0));
    });
  });

  group('the report is deterministic and bounded', () {
    test('the same PCM produces the same snapshot JSON', () {
      final signal = _signal();
      final first = runRecognitionShadow(
        RecognitionShadowRequest(
          pcm: signal,
          sampleRate: _sr,
          gate: _openGate,
        ),
      );
      final second = runRecognitionShadow(
        RecognitionShadowRequest(
          pcm: signal,
          sampleRate: _sr,
          gate: _openGate,
        ),
      );
      expect(first.toJson().toString(), second.toJson().toString());
      expect(first.strum.observedFrames, greaterThan(0));
    });

    test('the strum band records a rate only when it compared something', () {
      final snapshot = runRecognitionShadow(
        RecognitionShadowRequest(
          pcm: _signal(),
          sampleRate: _sr,
          gate: _openGate,
        ),
      );
      final strum = snapshot.strum;
      if (strum.comparedVerdicts == 0) {
        expect(strum.agreementRate, isNull);
      } else {
        expect(strum.agreementRate, inInclusiveRange(0.0, 1.0));
      }
      // With no CRNN weights the heuristic path runs, so there is no model
      // verdict — which must be COUNTED, not silently treated as agreement.
      expect(
        strum.candidateUnavailableFrames + strum.candidateVerdicts,
        strum.observedFrames,
      );
    });

    test('the sample ring never exceeds its capacity on a long stream', () {
      final snapshot = runRecognitionShadow(
        RecognitionShadowRequest(
          pcm: karplusStrongStrumPattern(
            cMajorFreqs,
            count: 12,
            sampleRate: _sr,
          ),
          sampleRate: _sr,
          gate: _openGate,
          ringCapacity: 8,
        ),
      );
      expect(snapshot.strumSamples.length, lessThanOrEqualTo(8));
      expect(snapshot.ringCapacity, 8);
    });

    test('a mode travels WITH the report', () {
      final snapshot = runRecognitionShadow(
        RecognitionShadowRequest(
          pcm: _signal(),
          sampleRate: _sr,
          gate: _openGate,
          mode: RecognitionMode.guided,
        ),
      );
      expect(snapshot.mode, RecognitionMode.guided);
      expect(snapshot.toJson()['mode'], 'guided');
      expect(snapshot.toJson()['strumStage'], 'shadow');
    });
  });

  group('chord agreement folds into the matrix', () {
    test('a constant candidate against silence lands in the N.C. row', () {
      final recorder = RecognitionShadowRecorder();
      final pipe = LivePipeline(
        sampleRate: _sr,
        shadowObserver: ChordShadowObserver(
          recorder: recorder,
          candidate: _CountingCandidate(label: 'Am'),
        ),
      );
      _drive(pipe, Float64List(_sr)); // one second of digital silence
      final chord = recorder.chordAggregate;
      expect(chord.comparedFrames, greaterThan(0));
      expect(
        chord.countFor(
          ShadowChordClass.noChord,
          ShadowChordClass.parse('Am'),
        ),
        chord.comparedFrames,
      );
      expect(chord.productionNoChordOnly, chord.comparedFrames);
      expect(chord.exactAgreementRate, 0.0);
    });
  });
}
