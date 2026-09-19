import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/recognition/device_audio_profile.dart';
import 'package:strumsight/features/live/domain/recognition/signal_quality_snapshot.dart';
import 'package:strumsight/features/live/engine/dsp/quality_aware_preprocessor.dart';

/// A quality snapshot with the metrics this round's mechanism reads. Every
/// other metric stays `null` — the analyzer's honest "not measured", which
/// the stage must tolerate.
SignalQualitySnapshot snapshotOf(
  SignalQualityState state, {
  double? rmsDbfs,
  double? peakDbfs,
}) => SignalQualitySnapshot(state: state, rmsDbfs: rmsDbfs, peakDbfs: peakDbfs);

List<double> chunkOf(double value, {int length = 256}) =>
    List<double>.filled(length, value);

/// Feeds the same chunk value [times] times and returns the LAST output.
List<double> feed(
  QualityAwarePreprocessor stage,
  SignalQualitySnapshot snapshot, {
  required int times,
  double value = 0.1,
}) {
  var out = <double>[];
  for (var i = 0; i < times; i++) {
    out = stage.process(chunkOf(value), snapshot);
  }
  return out;
}

double linearGain(double db) => math.pow(10, db / 20).toDouble();

void main() {
  group('disabled (the shipped state)', () {
    test('hands back the caller\'s own list instance, bit-identical', () {
      final stage = QualityAwarePreprocessor();
      final input = chunkOf(0.25);
      final quiet = snapshotOf(
        SignalQualityState.tooQuiet,
        rmsDbfs: -55,
        peakDbfs: -50,
      );

      final out = stage.process(input, quiet);

      expect(identical(out, input), isTrue);
      expect(stage.appliedGainDb, 0);
      expect(stage.clampedSampleCount, 0);
      expect(
        stage.lastAdaptation,
        LivePreprocessingAdaptation.disabled,
        reason: 'a disabled stage must not even claim an identity transform',
      );
    });

    test('stays inert however degraded the snapshot gets', () {
      final stage = QualityAwarePreprocessor();
      for (final state in SignalQualityState.values) {
        final input = chunkOf(0.02);
        final out = stage.process(
          input,
          snapshotOf(state, rmsDbfs: -58, peakDbfs: -52),
        );
        expect(identical(out, input), isTrue, reason: state.name);
        expect(stage.appliedGainDb, 0, reason: state.name);
      }
    });
  });

  group('enabled — level normalisation', () {
    test('a too-quiet input is boosted towards the target RMS, slewed', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );
      final quiet = snapshotOf(
        SignalQualityState.tooQuiet,
        rmsDbfs: -50,
        peakDbfs: -44,
      );

      final out = stage.process(chunkOf(0.1), quiet);

      // Wanted: -21 - (-50) = +29 dB, bounded to +12 dB, then slew-limited
      // to one step of 1.5 dB on the first chunk.
      expect(
        stage.appliedGainDb,
        closeTo(LivePreprocessingConfig.defaultMaxGainStepDb, 1e-12),
      );
      expect(stage.lastAdaptation, LivePreprocessingAdaptation.levelNormalised);
      expect(out.first, closeTo(0.1 * linearGain(1.5), 1e-12));
    });

    test('the boost saturates at the policy bound and stops there', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );
      final quiet = snapshotOf(
        SignalQualityState.tooQuiet,
        rmsDbfs: -50,
        peakDbfs: -44,
      );

      feed(stage, quiet, times: 40, value: 0.01);

      expect(
        stage.appliedGainDb,
        closeTo(LivePreprocessingConfig.defaultMaxBoostDb, 1e-12),
      );
    });

    test('a too-loud input is cut towards the target RMS', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );
      final loud = snapshotOf(
        SignalQualityState.tooLoud,
        rmsDbfs: -5,
        peakDbfs: -1.5,
      );

      final out = feed(stage, loud, times: 2, value: 0.5);

      // Wanted: -21 - (-5) = -16 dB, bounded to -12 dB, reached in steps of
      // 1.5 dB — two chunks in it is at -3 dB.
      expect(stage.appliedGainDb, closeTo(-3, 1e-12));
      expect(out.first, closeTo(0.5 * linearGain(-3), 1e-12));
    });

    test('a level state with no measured RMS applies no level correction', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );
      final input = chunkOf(0.1);

      final out = stage.process(input, snapshotOf(SignalQualityState.tooQuiet));

      expect(
        identical(out, input),
        isTrue,
        reason: 'an unmeasured level must not be replaced by a guess',
      );
      expect(stage.appliedGainDb, 0);
      expect(
        stage.lastAdaptation,
        LivePreprocessingAdaptation.deviceOffsetOnly,
      );
    });

    test('the peak-headroom bound refuses a boost that would clip', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );
      final input = chunkOf(0.9);

      // RMS says "quiet" (a spiky signal), but the peak is already at
      // -0.5 dBFS: the safe boost is negative, so no boost may happen.
      final out = stage.process(
        input,
        snapshotOf(SignalQualityState.tooQuiet, rmsDbfs: -50, peakDbfs: -0.5),
      );

      expect(identical(out, input), isTrue);
      expect(stage.appliedGainDb, 0);
    });
  });

  group('enabled — clipping', () {
    test('clipping never triggers a new gain and holds the current one', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );
      final quiet = snapshotOf(
        SignalQualityState.tooQuiet,
        rmsDbfs: -50,
        peakDbfs: -44,
      );
      feed(stage, quiet, times: 3, value: 0.01);
      final held = stage.appliedGainDb;
      expect(held, closeTo(4.5, 1e-12));

      final clipping = snapshotOf(
        SignalQualityState.clipping,
        rmsDbfs: -2,
        peakDbfs: 0,
      );
      feed(stage, clipping, times: 5, value: 0.01);

      expect(
        stage.appliedGainDb,
        closeTo(held, 1e-12),
        reason: 'a clipped signal is damaged: neither boost nor cut helps',
      );
      expect(stage.lastAdaptation, LivePreprocessingAdaptation.clippingHold);
    });

    test('clipping from a cold start leaves the input untouched', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );
      final input = chunkOf(0.99);

      final out = stage.process(
        input,
        snapshotOf(SignalQualityState.clipping, rmsDbfs: -1, peakDbfs: 0),
      );

      expect(identical(out, input), isTrue);
      expect(stage.appliedGainDb, 0);
      expect(stage.lastAdaptation, LivePreprocessingAdaptation.clippingHold);
    });
  });

  group('device profile', () {
    test('the identity profile contributes exactly 0 dB on a good signal', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );
      final input = chunkOf(0.3);

      final out = feed(
        stage,
        snapshotOf(SignalQualityState.good, rmsDbfs: -21, peakDbfs: -9),
        times: 5,
        value: 0.3,
      );

      expect(stage.appliedGainDb, 0);
      expect(out.length, input.length);
      expect(
        stage.lastAdaptation,
        LivePreprocessingAdaptation.deviceOffsetOnly,
        reason: 'the DECISION is reported even when it comes to 0 dB',
      );
    });

    test('a measured profile offset is applied even on a good signal', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
        deviceProfile: DeviceAudioProfile.measured(
          profileId: 'wizard-run-1',
          inputGainOffsetDb: 3,
          noiseFloorDbfs: -62,
        ),
      );

      feed(
        stage,
        snapshotOf(SignalQualityState.good, rmsDbfs: -21, peakDbfs: -9),
        times: 4,
        value: 0.2,
      );

      expect(stage.appliedGainDb, closeTo(3, 1e-12));
      expect(
        stage.lastAdaptation,
        LivePreprocessingAdaptation.deviceOffsetOnly,
      );
    });

    test('the profile offset rides on top of the level correction', () {
      final stage = QualityAwarePreprocessor(
        config: LivePreprocessingConfig.tuned(
          targetRmsDbfs: -21,
          maxBoostDb: 12,
          maxCutDb: 12,
          maxGainStepDb: 12,
        ),
        deviceProfile: DeviceAudioProfile.measured(
          profileId: 'wizard-run-2',
          inputGainOffsetDb: -4,
        ),
      );

      stage.process(
        chunkOf(0.05),
        snapshotOf(SignalQualityState.tooQuiet, rmsDbfs: -29, peakDbfs: -23),
      );

      // (-21 - -29) + (-4) = +4 dB, inside every bound and reachable in one
      // step with the widened slew.
      expect(stage.appliedGainDb, closeTo(4, 1e-12));
    });

    test('measured() refuses values a buggy wizard could produce', () {
      expect(
        () => DeviceAudioProfile.measured(profileId: ' ', inputGainOffsetDb: 0),
        throwsArgumentError,
      );
      expect(
        () => DeviceAudioProfile.measured(
          profileId: 'x',
          inputGainOffsetDb: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => DeviceAudioProfile.measured(
          profileId: 'x',
          inputGainOffsetDb: DeviceAudioProfile.maxInputGainOffsetDb + 0.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => DeviceAudioProfile.measured(
          profileId: 'x',
          inputGainOffsetDb: 0,
          noiseFloorDbfs: 3,
        ),
        throwsArgumentError,
      );
    });

    test('a profile survives a JSON round trip, identity included', () {
      const identity = DeviceAudioProfile.identity();
      expect(DeviceAudioProfile.fromJson(identity.toJson()), equals(identity));

      final measured = DeviceAudioProfile.measured(
        profileId: 'wizard-run-3',
        inputGainOffsetDb: -2.5,
        noiseFloorDbfs: -58,
      );
      expect(DeviceAudioProfile.fromJson(measured.toJson()), equals(measured));

      expect(
        () => DeviceAudioProfile.fromJson(const <String, Object?>{
          'profileId': 'x',
          'inputGainOffsetDb': 0,
        }),
        throwsArgumentError,
        reason: 'a MISSING key is not the same as an explicit null (L619)',
      );
    });
  });

  group('mechanism invariants', () {
    test('the transform is ONE scalar per chunk — no time distortion', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );
      final quiet = snapshotOf(
        SignalQualityState.tooQuiet,
        rmsDbfs: -50,
        peakDbfs: -44,
      );
      final input = <double>[
        for (var i = 0; i < 512; i++) 0.05 * math.sin(i / 7),
      ];

      final out = stage.process(input, quiet);

      expect(out.length, input.length);
      final gain = linearGain(stage.appliedGainDb);
      for (var i = 0; i < input.length; i++) {
        expect(
          out[i],
          closeTo(input[i] * gain, 1e-12),
          reason: 'sample $i must be the SAME scalar multiple as every other',
        );
      }
      expect(
        stage.clampedSampleCount,
        0,
        reason: 'nothing may be lost at these levels',
      );
    });

    test('with nothing clamped the transform is exactly invertible', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );
      final input = <double>[
        for (var i = 0; i < 128; i++) 0.01 * math.cos(i / 3),
      ];

      final out = stage.process(
        input,
        snapshotOf(SignalQualityState.tooQuiet, rmsDbfs: -55, peakDbfs: -48),
      );

      expect(stage.clampedSampleCount, 0);
      final gain = linearGain(stage.appliedGainDb);
      for (var i = 0; i < input.length; i++) {
        expect(out[i] / gain, closeTo(input[i], 1e-12));
      }
    });

    test('the safety clamp is COUNTED, never silently swallowed', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );

      // No measured peak, so the peak-headroom bound cannot engage: the
      // stage boosts and the ±1.0 rail catches what is left. The point of
      // the cell is that the loss is REPORTED.
      final out = stage.process(
        chunkOf(0.95, length: 16),
        snapshotOf(SignalQualityState.tooQuiet, rmsDbfs: -50),
      );

      expect(stage.appliedGainDb, greaterThan(0));
      expect(stage.clampedSampleCount, 16);
      expect(out.every((value) => value == 1.0), isTrue);
    });

    test('reset returns the stage to its constructed state', () {
      final stage = QualityAwarePreprocessor(
        config: const LivePreprocessingConfig.standard(),
      );
      feed(
        stage,
        snapshotOf(SignalQualityState.tooQuiet, rmsDbfs: -50, peakDbfs: -44),
        times: 4,
        value: 0.95,
      );
      expect(stage.appliedGainDb, greaterThan(0));

      stage.reset();

      expect(stage.appliedGainDb, 0);
      expect(stage.clampedSampleCount, 0);
      expect(stage.lastAdaptation, LivePreprocessingAdaptation.identity);
    });

    test('tuned() refuses a sweep point outside the safety envelope', () {
      expect(
        () => LivePreprocessingConfig.tuned(
          targetRmsDbfs: -21,
          maxBoostDb: LivePreprocessingConfig.absoluteGainLimitDb + 1,
          maxCutDb: 12,
          maxGainStepDb: 1.5,
        ),
        throwsArgumentError,
      );
      expect(
        () => LivePreprocessingConfig.tuned(
          targetRmsDbfs: 5,
          maxBoostDb: 12,
          maxCutDb: 12,
          maxGainStepDb: 1.5,
        ),
        throwsArgumentError,
      );
      expect(
        () => LivePreprocessingConfig.tuned(
          targetRmsDbfs: -21,
          maxBoostDb: 12,
          maxCutDb: 12,
          maxGainStepDb: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
