import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/analyze/engine/clip_analyzer.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/rhythm/beat_grid.dart';
import 'package:strumsight/features/audio_analysis/engine/rhythm/beat_grid_estimator.dart';
import 'package:strumsight/features/audio_analysis/engine/rhythm/tempo_curve_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/rhythm/tempo_hypothesis.dart';

import '../../../support/synth.dart';

Duration _sec(double seconds) =>
    Duration(microseconds: (seconds * 1e6).round());

List<Duration> _evenlySpaced(
  int count,
  double gapSeconds, {
  double startSeconds = 0,
}) => [for (var i = 0; i < count; i++) _sec(startSeconds + gapSeconds * i)];

void main() {
  group('legacy BPM parity (tempo.legacy_bpm.v1)', () {
    const builder = TempoCurveBuilder();

    test('fewer than two events yields 0, same as V1', () {
      final curve = builder.build(
        eventTimes: const <Duration>[Duration.zero],
        clipDuration: const Duration(seconds: 1),
      );
      expect(curve.legacyBpm, 0);
    });

    test('all near-simultaneous events (dt <= 0.05s) yields 0', () {
      final events = _evenlySpaced(5, 0.02);
      final curve = builder.build(
        eventTimes: events,
        clipDuration: const Duration(seconds: 1),
      );
      expect(curve.legacyBpm, 0);
    });

    test('steady 0.5s interval clamps to exactly 120 BPM', () {
      final events = _evenlySpaced(10, 0.5);
      final curve = builder.build(
        eventTimes: events,
        clipDuration: const Duration(seconds: 5),
      );
      expect(curve.legacyBpm, closeTo(120, 1e-9));
    });

    test('very fast intervals clamp at the 300 BPM ceiling', () {
      // 60/0.1 = 600 BPM raw, must clamp to exactly 300.
      final events = _evenlySpaced(10, 0.1);
      final curve = builder.build(
        eventTimes: events,
        clipDuration: const Duration(seconds: 5),
      );
      expect(curve.legacyBpm, closeTo(300, 1e-9));
    });

    test('very slow intervals clamp at the 30 BPM floor', () {
      // 60/3 = 20 BPM raw, must clamp to exactly 30.
      final events = _evenlySpaced(10, 3);
      final curve = builder.build(
        eventTimes: events,
        clipDuration: const Duration(seconds: 30),
      );
      expect(curve.legacyBpm, closeTo(30, 1e-9));
    });

    test('adapts the real ClipAnalyzer._bpmFromStrums output bit-for-bit', () {
      const legacy = ClipAnalyzer();
      for (final gapSeconds in <double>[0.4, 0.5, 0.75]) {
        final samples = strumPattern(
          lowFirstPerStrum: const [true, false, true, false, true],
          gapSeconds: gapSeconds,
        );
        final result = legacy.analyze(samples, 44100);
        final events = [for (final strum in result.strums) _sec(strum.timeSec)];
        final curve = builder.build(
          eventTimes: events,
          clipDuration: _sec(result.durationSec),
        );
        // Strum times pass through microsecond-precision Duration (the
        // domain's time type everywhere else in R12), so this is not the
        // exact-Duration-fixture 1e-9 bit-parity check above — it is a
        // real-signal cross-check bounded by that microsecond quantization.
        expect(
          curve.legacyBpm,
          closeTo(result.bpm, 1e-3),
          reason: 'gapSeconds=$gapSeconds',
        );
      }
    });
  });

  group('minimum event-count threshold (7 / 8 / 9, inclusive at 8)', () {
    const builder = TempoCurveBuilder();

    test('7 events -> unavailable, insufficientEvents', () {
      final curve = builder.build(
        eventTimes: _evenlySpaced(7, 0.5),
        clipDuration: const Duration(seconds: 10),
      );
      expect(curve.status, CapabilityStatus.unavailable);
      expect(curve.reason, CapabilityUnavailableReason.insufficientEvents);
    });

    test('8 events (on the boundary, inclusive) -> available', () {
      final curve = builder.build(
        eventTimes: _evenlySpaced(8, 0.5),
        clipDuration: const Duration(seconds: 10),
      );
      expect(curve.status, CapabilityStatus.available);
    });

    test('9 events -> available', () {
      final curve = builder.build(
        eventTimes: _evenlySpaced(9, 0.5),
        clipDuration: const Duration(seconds: 10),
      );
      expect(curve.status, CapabilityStatus.available);
    });
  });

  group('minimum clip-duration threshold (3.999s / 4.0s / 4.001s)', () {
    const builder = TempoCurveBuilder();
    final events = _evenlySpaced(10, 0.1);

    test('3.999s -> unavailable, insufficientEvents', () {
      final curve = builder.build(
        eventTimes: events,
        clipDuration: const Duration(microseconds: 3999000),
      );
      expect(curve.status, CapabilityStatus.unavailable);
      expect(curve.reason, CapabilityUnavailableReason.insufficientEvents);
    });

    test('4.0s (on the boundary, inclusive) -> available', () {
      final curve = builder.build(
        eventTimes: events,
        clipDuration: const Duration(microseconds: 4000000),
      );
      expect(curve.status, CapabilityStatus.available);
    });

    test('4.001s -> available', () {
      final curve = builder.build(
        eventTimes: events,
        clipDuration: const Duration(microseconds: 4001000),
      );
      expect(curve.status, CapabilityStatus.available);
    });
  });

  group('half/double-time ambiguity (OD-02)', () {
    test('55 BPM below the band publishes 110 with 0.7x confidence', () {
      final resolved = TempoHypothesisSet.resolve(
        rawBpm: 55,
        rawConfidence: 0.8,
      );
      expect(resolved.hypotheses.length, 2);
      final bpms = resolved.hypotheses.map((h) => h.bpm).toSet();
      expect(bpms, containsAll(<double>[55, 110]));
      expect(resolved.published.bpm, closeTo(110, 1e-9));
      expect(resolved.published.confidence, closeTo(0.8 * 0.7, 1e-9));
    });

    test(
      '120 BPM inside the band publishes a single, unpenalised hypothesis',
      () {
        final resolved = TempoHypothesisSet.resolve(
          rawBpm: 120,
          rawConfidence: 0.8,
        );
        expect(resolved.hypotheses.length, 1);
        expect(resolved.published.bpm, closeTo(120, 1e-9));
        expect(resolved.published.confidence, closeTo(0.8, 1e-9));
      },
    );

    test('a steady 120 BPM curve carries a single hypothesis, no penalty', () {
      const builder = TempoCurveBuilder();
      final curve = builder.build(
        eventTimes: _evenlySpaced(10, 0.5),
        clipDuration: const Duration(seconds: 6),
      );
      expect(curve.hypotheses.length, 1);
      expect(curve.hypotheses.single.isPublished, isTrue);
    });

    test('an ambiguous curve keeps both hypotheses with the 0.7x penalty', () {
      const builder = TempoCurveBuilder();
      // 60/1.6 = 37.5 BPM raw (below the preferred band).
      final curve = builder.build(
        eventTimes: _evenlySpaced(10, 1.6),
        clipDuration: const Duration(seconds: 20),
      );
      expect(curve.hypotheses.length, 2);
      final unpublished = curve.hypotheses.firstWhere((h) => !h.isPublished);
      final published = curve.hypotheses.firstWhere((h) => h.isPublished);
      expect(published.confidence, closeTo(unpublished.confidence * 0.7, 1e-9));
    });
  });

  group('stable-region threshold (median ±5%, inclusive)', () {
    test('113.9 BPM (below the band) is not stable', () {
      expect(
        TempoCurveBuilder.isStableLocalBpm(localBpm: 113.9, medianBpm: 120),
        isFalse,
      );
    });

    test('114.0 BPM (= 120*0.95, on the boundary) is stable', () {
      expect(
        TempoCurveBuilder.isStableLocalBpm(localBpm: 114.0, medianBpm: 120),
        isTrue,
      );
    });

    test('114.1 BPM (inside the band) is stable', () {
      expect(
        TempoCurveBuilder.isStableLocalBpm(localBpm: 114.1, medianBpm: 120),
        isTrue,
      );
    });
  });

  group('no free-play metre assertion', () {
    test(
      'free-play beatsPerBar is legacyDefault=4 and meter is notApplicable',
      () {
        const estimator = BeatGridEstimator();
        final grid = estimator.estimate(
          eventTimes: _evenlySpaced(9, 0.5),
          clipDuration: const Duration(seconds: 5),
        );
        expect(grid.beatsPerBar, 4);
        expect(grid.beatsPerBarSource, BeatsPerBarSource.legacyDefault);
        expect(grid.meterStatus, CapabilityStatus.notApplicable);
      },
    );
  });

  group('tempo fixture matrix — full BeatGrid + TempoCurve', () {
    const estimator = BeatGridEstimator();
    const builder = TempoCurveBuilder();

    test('60 BPM steady', () {
      final events = _evenlySpaced(10, 1.0);
      final grid = estimator.estimate(
        eventTimes: events,
        clipDuration: const Duration(seconds: 9),
      );
      final curve = builder.build(
        eventTimes: events,
        clipDuration: const Duration(seconds: 9),
      );
      expect(grid.status, CapabilityStatus.available);
      expect(curve.status, CapabilityStatus.available);
      expect(curve.legacyBpm, closeTo(60, 1e-9));
      expect(curve.medianBpm, closeTo(60, 1e-6));
    });

    test('120 BPM steady', () {
      final events = _evenlySpaced(10, 0.5);
      final grid = estimator.estimate(
        eventTimes: events,
        clipDuration: const Duration(seconds: 5),
      );
      final curve = builder.build(
        eventTimes: events,
        clipDuration: const Duration(seconds: 5),
      );
      expect(grid.status, CapabilityStatus.available);
      expect(curve.legacyBpm, closeTo(120, 1e-9));
      expect(curve.medianBpm, closeTo(120, 1e-6));
    });

    test('synthetic accelerando 60 -> 90 BPM has positive drift', () {
      final events = <Duration>[];
      var t = 0.0;
      const steps = 12;
      for (var i = 0; i <= steps; i++) {
        events.add(_sec(t));
        final progress = i / steps;
        final periodSeconds = 1.0 - progress * (1.0 - 60 / 90);
        t += periodSeconds;
      }
      final clipDuration = _sec(t + 0.5);
      final grid = estimator.estimate(
        eventTimes: events,
        clipDuration: clipDuration,
      );
      final curve = builder.build(
        eventTimes: events,
        clipDuration: clipDuration,
      );
      expect(grid.status, CapabilityStatus.available);
      expect(curve.status, CapabilityStatus.available);
      expect(curve.driftSlopeBpmPerMinute, isNotNull);
      expect(curve.driftSlopeBpmPerMinute!, greaterThan(0));
    });

    test('synthetic ritardando 120 -> 90 BPM has negative drift', () {
      final events = <Duration>[];
      var t = 0.0;
      const steps = 12;
      for (var i = 0; i <= steps; i++) {
        events.add(_sec(t));
        final progress = i / steps;
        final periodSeconds = 0.5 + progress * (60 / 90 - 0.5);
        t += periodSeconds;
      }
      final clipDuration = _sec(t + 0.5);
      final grid = estimator.estimate(
        eventTimes: events,
        clipDuration: clipDuration,
      );
      final curve = builder.build(
        eventTimes: events,
        clipDuration: clipDuration,
      );
      expect(grid.status, CapabilityStatus.available);
      expect(curve.status, CapabilityStatus.available);
      expect(curve.driftSlopeBpmPerMinute, isNotNull);
      expect(curve.driftSlopeBpmPerMinute!, lessThan(0));
    });

    test(
      'irregular (jittered, deterministic) onsets still produce a valid curve',
      () {
        const gapsSeconds = [
          0.4,
          0.6,
          0.55,
          0.45,
          0.5,
          0.65,
          0.4,
          0.5,
          0.6,
          0.45,
        ];
        final events = <Duration>[];
        var t = 0.0;
        for (final gap in gapsSeconds) {
          events.add(_sec(t));
          t += gap;
        }
        final clipDuration = _sec(t + 0.5);
        final grid = estimator.estimate(
          eventTimes: events,
          clipDuration: clipDuration,
        );
        final curve = builder.build(
          eventTimes: events,
          clipDuration: clipDuration,
        );
        expect(grid.status, CapabilityStatus.available);
        expect(curve.status, CapabilityStatus.available);
        expect(curve.medianBpm, isNotNull);
        expect(curve.medianBpm!.isFinite, isTrue);
      },
    );

    test(
      '7 events (below the minimum) — grid may still exist, curve does not',
      () {
        final events = _evenlySpaced(7, 0.5);
        final grid = estimator.estimate(
          eventTimes: events,
          clipDuration: const Duration(seconds: 5),
        );
        final curve = builder.build(
          eventTimes: events,
          clipDuration: const Duration(seconds: 5),
        );
        expect(grid.status, CapabilityStatus.available);
        expect(curve.status, CapabilityStatus.unavailable);
        expect(curve.reason, CapabilityUnavailableReason.insufficientEvents);
      },
    );

    test('8 events (on the minimum) — both grid and curve available', () {
      final events = _evenlySpaced(8, 0.5);
      final grid = estimator.estimate(
        eventTimes: events,
        clipDuration: const Duration(seconds: 5),
      );
      final curve = builder.build(
        eventTimes: events,
        clipDuration: const Duration(seconds: 5),
      );
      expect(grid.status, CapabilityStatus.available);
      expect(curve.status, CapabilityStatus.available);
    });

    test('3/4 target grid — target-first, 3 beats per bar', () {
      final beatTimes = _evenlySpaced(9, 0.5);
      final target = BeatGridTargetInput(beatTimes: beatTimes, beatsPerBar: 3);
      final grid = estimator.estimate(
        eventTimes: const <Duration>[],
        clipDuration: const Duration(seconds: 5),
        target: target,
      );
      final curve = builder.build(
        eventTimes: beatTimes,
        clipDuration: const Duration(seconds: 5),
      );
      expect(grid.beatsPerBar, 3);
      expect(grid.beatsPerBarSource, BeatsPerBarSource.target);
      expect(grid.bars.length, 3);
      expect(curve.status, CapabilityStatus.available);
    });

    test('4/4 target grid — target-first, 4 beats per bar', () {
      final beatTimes = _evenlySpaced(8, 0.5);
      final target = BeatGridTargetInput(beatTimes: beatTimes, beatsPerBar: 4);
      final grid = estimator.estimate(
        eventTimes: const <Duration>[],
        clipDuration: const Duration(seconds: 5),
        target: target,
      );
      final curve = builder.build(
        eventTimes: beatTimes,
        clipDuration: const Duration(seconds: 5),
      );
      expect(grid.beatsPerBar, 4);
      expect(grid.beatsPerBarSource, BeatsPerBarSource.target);
      expect(grid.bars.length, 2);
      expect(curve.status, CapabilityStatus.available);
    });
  });

  group('TempoCurve constructor rejects non-finite/out-of-range summaries', () {
    TempoCurve buildWith({
      double? medianBpm,
      double? iqrBpm,
      double? driftSlopeBpmPerMinute,
      double? stableRegionRatio,
    }) => TempoCurve(
      status: CapabilityStatus.available,
      legacyBpm: 120,
      medianBpm: medianBpm,
      iqrBpm: iqrBpm,
      driftSlopeBpmPerMinute: driftSlopeBpmPerMinute,
      stableRegionRatio: stableRegionRatio,
    );

    test('NaN medianBpm throws', () {
      expect(() => buildWith(medianBpm: double.nan), throwsArgumentError);
    });

    test('infinite medianBpm throws', () {
      expect(() => buildWith(medianBpm: double.infinity), throwsArgumentError);
    });

    test('non-positive medianBpm throws', () {
      expect(() => buildWith(medianBpm: 0), throwsArgumentError);
    });

    test('medianBpm above 400 throws', () {
      expect(() => buildWith(medianBpm: 400.1), throwsArgumentError);
    });

    test('medianBpm of exactly 400 is accepted', () {
      expect(() => buildWith(medianBpm: 400), returnsNormally);
    });

    test('NaN iqrBpm throws', () {
      expect(() => buildWith(iqrBpm: double.nan), throwsArgumentError);
    });

    test('infinite iqrBpm throws', () {
      expect(() => buildWith(iqrBpm: double.infinity), throwsArgumentError);
    });

    test('negative iqrBpm throws', () {
      expect(() => buildWith(iqrBpm: -1), throwsArgumentError);
    });

    test('NaN driftSlopeBpmPerMinute throws', () {
      expect(
        () => buildWith(driftSlopeBpmPerMinute: double.nan),
        throwsArgumentError,
      );
    });

    test('infinite driftSlopeBpmPerMinute throws', () {
      expect(
        () => buildWith(driftSlopeBpmPerMinute: double.negativeInfinity),
        throwsArgumentError,
      );
    });

    test('negative driftSlopeBpmPerMinute is accepted', () {
      expect(() => buildWith(driftSlopeBpmPerMinute: -5), returnsNormally);
    });

    test('NaN stableRegionRatio throws', () {
      expect(
        () => buildWith(stableRegionRatio: double.nan),
        throwsArgumentError,
      );
    });

    test('infinite stableRegionRatio throws', () {
      expect(
        () => buildWith(stableRegionRatio: double.infinity),
        throwsArgumentError,
      );
    });

    test('stableRegionRatio below 0 throws', () {
      expect(() => buildWith(stableRegionRatio: -0.01), throwsArgumentError);
    });

    test('stableRegionRatio above 1 throws', () {
      expect(() => buildWith(stableRegionRatio: 1.01), throwsArgumentError);
    });

    test('stableRegionRatio boundary values 0 and 1 are accepted', () {
      expect(() => buildWith(stableRegionRatio: 0), returnsNormally);
      expect(() => buildWith(stableRegionRatio: 1), returnsNormally);
    });
  });
}
