import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/recognition/device_audio_profile.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/dsp/quality_aware_preprocessor.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

import '../../../support/synth.dart';

const _sr = 44100;

/// Everything an emitted [LiveFrame] carries, flattened into ONE comparable
/// string. Two runs whose digest lists are equal emitted the same frames, in
/// the same order, with the same chord/strum/tempo/time content — which is
/// what "the DSP path cannot observe that the stage exists" means for a
/// caller of `addChunk`.
String _digest(LiveFrame frame) => <Object?>[
  frame.current?.label,
  frame.next?.label,
  frame.latestStrum?.direction.name,
  frame.latestStrum?.confidence,
  frame.bpm,
  frame.inputLevel,
  frame.tuningHz,
  frame.listening,
  frame.strumSeq,
  frame.latestStrumTime,
  frame.onsetTimeSec,
  frame.engineTimeSec,
  frame.chordDecision?.name,
  frame.chordRejectReason?.name,
  for (final slot in frame.bar)
    '${slot.label}/${slot.isDownbeat}/${slot.strum?.direction.name}',
].join('|');

/// Feeds [signal] in mic-like ~23 ms chunks, the way every other pipeline
/// test in this tree drives [LivePipeline].
List<LiveFrame> _run(LivePipeline pipeline, Float64List signal) {
  final frames = <LiveFrame>[];
  for (var i = 0; i < signal.length; i += 1024) {
    final end = (i + 1024 < signal.length) ? i + 1024 : signal.length;
    frames.addAll(pipeline.addChunk(signal.sublist(i, end)));
  }
  return frames;
}

/// A non-identity device profile, to prove that the per-device correction is
/// inert on its own: only the flag can let it reach a sample.
DeviceAudioProfile _measuredProfile() => DeviceAudioProfile.measured(
  profileId: 'wizard-run-test',
  inputGainOffsetDb: 6,
);

void main() {
  group('E14-R31: the SHIPPED path (recognitionPreprocessingEnabled off)', () {
    test('a disabled stage leaves every emitted frame bit-identical', () {
      final signal = chordSignal(cMajorFreqs, seconds: 1.5);
      final reference = _run(LivePipeline(sampleRate: _sr), signal);
      final disabled = _run(
        LivePipeline(
          sampleRate: _sr,
          preprocessing: const LivePreprocessingConfig.disabled(),
          deviceProfile: _measuredProfile(),
        ),
        signal,
      );

      expect(reference, isNotEmpty);
      expect(
        disabled.map(_digest).toList(),
        reference.map(_digest).toList(),
        reason:
            'with the flag off not one sample may change — a measured '
            'device profile included (ADR 0552 D1/D4)',
      );
    });

    test('the disabled stage reports itself as inert, never as identity', () {
      final pipeline = LivePipeline(
        sampleRate: _sr,
        deviceProfile: _measuredProfile(),
      );

      _run(pipeline, chordSignal(cMajorFreqs, seconds: 1.0));

      expect(pipeline.preprocessingGainDb, 0);
      expect(pipeline.preprocessingClampedSampleCount, 0);
      expect(
        pipeline.preprocessingAdaptation,
        LivePreprocessingAdaptation.disabled,
        reason:
            '"switched off" and "ran and decided to change nothing" are '
            'different facts',
      );
    });

    test('reset leaves the disabled stage inert', () {
      final pipeline = LivePipeline(sampleRate: _sr);

      _run(pipeline, chordSignal(cMajorFreqs, seconds: 0.6));
      pipeline.reset();

      expect(pipeline.preprocessingGainDb, 0);
      expect(pipeline.preprocessingClampedSampleCount, 0);
      expect(
        pipeline.preprocessingAdaptation,
        LivePreprocessingAdaptation.disabled,
      );
    });
  });

  group('E14-R31: the ENABLED stage is a mechanism, not a tuning', () {
    test('a zero-envelope policy runs, decides, and still changes nothing', () {
      final signal = chordSignal(cMajorFreqs, seconds: 1.5);
      final reference = _run(LivePipeline(sampleRate: _sr), signal);
      final pipeline = LivePipeline(
        sampleRate: _sr,
        // Enabled, but the gain envelope is zero on both sides: the stage
        // makes its decision every chunk and the bounds refuse to let it
        // act. This is the cell that pins the BOUNDS, not the flag.
        preprocessing: LivePreprocessingConfig.tuned(
          targetRmsDbfs: LivePreprocessingConfig.defaultTargetRmsDbfs,
          maxBoostDb: 0,
          maxCutDb: 0,
          maxGainStepDb: 0.01,
        ),
        deviceProfile: _measuredProfile(),
      );

      final bounded = _run(pipeline, signal);

      expect(
        bounded.map(_digest).toList(),
        reference.map(_digest).toList(),
        reason: 'a bound of 0 dB is a bound, not a suggestion',
      );
      expect(pipeline.preprocessingGainDb, 0);
      expect(pipeline.preprocessingClampedSampleCount, 0);
      expect(
        pipeline.preprocessingAdaptation,
        isNot(LivePreprocessingAdaptation.disabled),
        reason: 'the stage IS enabled here — it decided, it did not sleep',
      );
    });

    test('the stage never moves a frame in time', () {
      // The emission clock counts RAW samples and the stage never changes a
      // chunk's LENGTH, so the frame cadence is a structural invariant: it
      // must hold at the full standard envelope, whatever gain the quality
      // snapshot asks for.
      final signal = strumPattern(
        lowFirstPerStrum: const [true, false, true, false],
        gapSeconds: 0.5,
      );
      final reference = _run(LivePipeline(sampleRate: _sr), signal);
      final pipeline = LivePipeline(
        sampleRate: _sr,
        preprocessing: const LivePreprocessingConfig.standard(),
      );

      final enabled = _run(pipeline, signal);

      expect(reference, isNotEmpty);
      expect(enabled.length, reference.length);
      expect(
        enabled.map((frame) => frame.engineTimeSec).toList(),
        reference.map((frame) => frame.engineTimeSec).toList(),
        reason: 'preprocessing must never shift the engine clock',
      );
    });

    test('an enabled stage stays inside its own safety envelope', () {
      final pipeline = LivePipeline(
        sampleRate: _sr,
        preprocessing: const LivePreprocessingConfig.standard(),
      );

      // Deliberately far below the quiet gate (-40 dBFS RMS), so the stage
      // has every reason to boost. The cell pins the ENVELOPE, not a tuned
      // amount: the amount is UNMEASURED until the 5-phone A/B exists.
      _run(pipeline, chordSignal(cMajorFreqs, seconds: 1.5, amp: 0.0015));

      expect(
        pipeline.preprocessingGainDb,
        inInclusiveRange(
          -LivePreprocessingConfig.defaultMaxCutDb,
          LivePreprocessingConfig.defaultMaxBoostDb,
        ),
      );
      expect(
        pipeline.preprocessingAdaptation,
        isNot(LivePreprocessingAdaptation.disabled),
      );
    });

    test('reset returns an enabled stage to 0 dB', () {
      final pipeline = LivePipeline(
        sampleRate: _sr,
        preprocessing: const LivePreprocessingConfig.standard(),
      );

      _run(pipeline, chordSignal(cMajorFreqs, seconds: 1.0, amp: 0.0015));
      pipeline.reset();

      expect(pipeline.preprocessingGainDb, 0);
      expect(pipeline.preprocessingClampedSampleCount, 0);
      expect(
        pipeline.preprocessingAdaptation,
        LivePreprocessingAdaptation.identity,
      );
    });
  });
}
