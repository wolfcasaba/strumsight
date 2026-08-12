import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

const int _sampleRate = 1000; // 1 sample == 1 ms, keeps indices readable.
const int _spacingMs = 200; // >> the 20 ms attack window: no overlap.
const double _quiet = 0.05; // well under the 0.999 clip threshold.

void main() {
  group('buildDynamicsMetrics — fixture matrix (brief §6)', () {
    test('equal-strength strokes: near-zero CV, no outliers', () {
      final events = _events(
        List<double>.filled(10, 1.0),
        List<StrumDirection>.filled(10, StrumDirection.down),
      );
      final report = _build(events);

      expect(
        _value(report, DynamicsMetricIds.strokeStrengthCv),
        closeTo(0, 1e-9),
      );
      expect(_value(report, DynamicsMetricIds.outlierRatio), closeTo(0, 1e-9));
    });

    test('monotonically increasing strength publishes positive drift', () {
      final strengths = <double>[for (var i = 0; i < 10; i++) 1.0 + i * 0.2];
      final events = _events(
        strengths,
        List<StrumDirection>.filled(10, StrumDirection.down),
      );
      final report = _build(events);

      expect(_value(report, DynamicsMetricIds.drift), greaterThan(0));
    });

    test('sparse accent fixture is detected by the target-gated metric', () {
      // python3 -c 'a sparse loud stroke every 4th event, verified against
      // the moving-median formula in docs/rag/chunks/022-…md: only indices
      // 0, 4, 8 exceed the 1.2 threshold ratio.'
      final strengths = <double>[
        for (var i = 0; i < 12; i++) i % 4 == 0 ? 2.0 : 1.0,
      ];
      final events = _events(
        strengths,
        List<StrumDirection>.filled(12, StrumDirection.down),
      );
      final expectedAccents = <String>{'e0', 'e4', 'e8'};
      final report = _build(events, expectedAccentEventIds: expectedAccents);

      expect(
        _result(report, DynamicsMetricIds.accentAccuracy).status,
        CapabilityStatus.available,
      );
      expect(
        _value(report, DynamicsMetricIds.accentAccuracy),
        closeTo(1.0, 1e-9),
      );
    });

    test('a single outlier stroke is reflected in the outlier ratio', () {
      final strengths = List<double>.filled(10, 1.0)..[5] = 5.0;
      final events = _events(
        strengths,
        List<StrumDirection>.filled(10, StrumDirection.down),
      );
      final report = _build(events);

      expect(
        _value(report, DynamicsMetricIds.outlierRatio),
        closeTo(1 / 10, 1e-9),
      );
    });

    test('a clipped attack is excluded from stroke-strength CV', () {
      // 20 total events keeps clippedEventRatio at exactly 1/20 = 0.05, the
      // inclusive `degraded` boundary — not `unavailable` — so the metric
      // still publishes a value to compare.
      final baseStrengths = <double>[
        for (var i = 0; i < 19; i++) 1.0 + (i % 5) * 0.1,
      ];
      final withoutClip = _events(
        baseStrengths,
        List<StrumDirection>.filled(19, StrumDirection.down),
      );
      final withClip = _events(<double>[
        ...baseStrengths,
        1.0,
      ], List<StrumDirection>.filled(20, StrumDirection.down));

      final reportA = _build(withoutClip);
      final reportB = _build(withClip, clippedIndices: const <int>{19});

      expect(reportB.gateStatus, CapabilityStatus.degraded);
      expect(
        _value(reportB, DynamicsMetricIds.strokeStrengthCv),
        closeTo(_value(reportA, DynamicsMetricIds.strokeStrengthCv), 1e-12),
      );
      expect(
        _value(reportB, DynamicsMetricIds.clippedEventRatio),
        closeTo(1 / 20, 1e-12),
      );
    });

    test('down twice as strong as up publishes a ~2.0 descriptive ratio', () {
      final directions = <StrumDirection>[
        for (var i = 0; i < 10; i++)
          i.isEven ? StrumDirection.down : StrumDirection.up,
      ];
      final strengths = <double>[
        for (var i = 0; i < 10; i++) i.isEven ? 2.0 : 1.0,
      ];
      final events = _events(strengths, directions);
      final report = _build(events);

      expect(
        _value(report, DynamicsMetricIds.downUpMedianRatio),
        closeTo(2.0, 1e-9),
      );
      final result = _result(report, DynamicsMetricIds.downUpMedianRatio);
      expect(result.value, isA<ScalarMetricValue>());
    });

    test('a quiet mid-session region raises the quiet-region ratio', () {
      final localRms = <double>[
        for (var i = 0; i < 12; i++) (i >= 4 && i < 8) ? 0.05 : 1.0,
      ];
      final events = _events(
        List<double>.filled(12, 1.0),
        List<StrumDirection>.filled(12, StrumDirection.down),
        localRms: localRms,
      );
      final report = _build(events);

      expect(
        _value(report, DynamicsMetricIds.quietRegionRatio),
        greaterThan(0),
      );
    });
  });

  group(
    'gain invariance and original-sample provenance (brief §6, ADR 0234)',
    () {
      test('×2 and ×0.5 amplitude scaling leaves ratios bit-identical', () {
        final directions = <StrumDirection>[
          for (var i = 0; i < 10; i++)
            i.isEven ? StrumDirection.down : StrumDirection.up,
        ];
        final baseStrengths = <double>[
          for (var i = 0; i < 10; i++) 1.0 + (i % 4) * 0.3,
        ];

        final reference = _build(_events(baseStrengths, directions));
        final doubled = _build(
          _events(<double>[for (final s in baseStrengths) s * 2], directions),
        );
        final halved = _build(
          _events(<double>[for (final s in baseStrengths) s * 0.5], directions),
        );

        for (final id in <String>[
          DynamicsMetricIds.strokeStrengthCv,
          DynamicsMetricIds.downUpMedianRatio,
          DynamicsMetricIds.outlierRatio,
        ]) {
          final base = _value(reference, id);
          expect(_value(doubled, id), closeTo(base, 1e-12), reason: id);
          expect(_value(halved, id), closeTo(base, 1e-12), reason: id);
        }
      });

      test(
        'clipping introduced only in canonicalSamples never changes the result '
        '(mutation-tested against reading canonicalSamples — brief §10)',
        () {
          final directions = List<StrumDirection>.filled(
            9,
            StrumDirection.down,
          );
          final strengths = <double>[
            for (var i = 0; i < 9; i++) 1.0 + (i % 3) * 0.4,
          ];
          final events = _events(strengths, directions);

          final baseline = _build(events);
          final withClippedCanonical = _build(
            events,
            canonicalOverride: (samples) {
              final mutated = List<double>.of(samples);
              for (var i = 0; i < mutated.length; i++) {
                mutated[i] = 1.0; // fully clipped canonical buffer.
              }
              return mutated;
            },
          );

          for (final id in DynamicsMetricIds.all) {
            expect(
              withClippedCanonical.metrics.firstWhere((m) => m.id == id).status,
              baseline.metrics.firstWhere((m) => m.id == id).status,
              reason: id,
            );
          }
          expect(
            _value(withClippedCanonical, DynamicsMetricIds.strokeStrengthCv),
            closeTo(
              _value(baseline, DynamicsMetricIds.strokeStrengthCv),
              1e-12,
            ),
          );
        },
      );
    },
  );

  group('outlier threshold triple — 2×MAD, inclusive (brief §6)', () {
    // python3 -c '
    // base = [0.9,0.9,0.9,0.9,1.1,1.1,1.1]
    // median = 1.0  # (0.9,0.9,0.9,0.9 | 1.1,1.1,1.1) with an 8th max value
    // mad = 0.1
    // print(1 + 1.99*mad, 1 + 2.00*mad, 1 + 2.01*mad)'
    // -> 1.199, 1.2, 1.201 (all > 1.1, so remain the attackStrength maximum
    // and MAD stays anchored to the 7-value baseline, as derived in
    // docs/rag/chunks/022-dynamics-stroke-balance.md).
    final baseline = <double>[0.9, 0.9, 0.9, 0.9, 1.1, 1.1, 1.1];
    final directions = List<StrumDirection>.filled(8, StrumDirection.down);

    test('1.99×MAD is not an outlier', () {
      final report = _build(_events(<double>[...baseline, 1.199], directions));
      expect(_value(report, DynamicsMetricIds.outlierRatio), closeTo(0, 1e-9));
    });

    test('exactly 2.00×MAD is not an outlier (inclusive boundary)', () {
      final report = _build(_events(<double>[...baseline, 1.2], directions));
      expect(_value(report, DynamicsMetricIds.outlierRatio), closeTo(0, 1e-9));
    });

    test('2.01×MAD is an outlier', () {
      final report = _build(_events(<double>[...baseline, 1.201], directions));
      expect(
        _value(report, DynamicsMetricIds.outlierRatio),
        closeTo(1 / 8, 1e-9),
      );
    });
  });

  group(
    'clipping-gate threshold triple — clippedEventRatio = 0.05 (brief §6)',
    () {
      final directions = List<StrumDirection>.filled(20, StrumDirection.down);
      final strengths = List<double>.filled(20, 1.0);

      test('0/20 clipped stays available', () {
        final events = _events(strengths, directions);
        final report = _build(events);
        expect(report.gateStatus, CapabilityStatus.available);
      });

      test('1/20 clipped (ratio 0.05) is degraded — inclusive boundary', () {
        final events = _events(strengths, directions);
        final report = _build(events, clippedIndices: const {0});
        expect(report.gateStatus, CapabilityStatus.degraded);
      });

      test('2/20 clipped (ratio 0.1) is unavailable — inputClipped', () {
        final events = _events(strengths, directions);
        final report = _build(events, clippedIndices: const {0, 1});
        expect(report.gateStatus, CapabilityStatus.unavailable);
        expect(report.gateReason, CapabilityUnavailableReason.inputClipped);
        for (final metric in report.metrics) {
          expect(metric.status, CapabilityStatus.unavailable);
          expect(
            metric.unavailableReason,
            CapabilityUnavailableReason.inputClipped,
          );
        }
      });
    },
  );

  group('noise-floor gate threshold triples (brief §6, OD-03)', () {
    final events = _events(
      List<double>.filled(10, 1.0),
      List<StrumDirection>.filled(10, StrumDirection.down),
    );

    test('-35.01 dBFS stays available', () {
      final report = _build(events, noiseFloorDbfs: -35.01);
      expect(report.gateStatus, CapabilityStatus.available);
    });

    test('-35.0 dBFS is degraded — inclusive boundary', () {
      final report = _build(events, noiseFloorDbfs: -35.0);
      expect(report.gateStatus, CapabilityStatus.degraded);
    });

    test('-34.99 dBFS is degraded', () {
      final report = _build(events, noiseFloorDbfs: -34.99);
      expect(report.gateStatus, CapabilityStatus.degraded);
    });

    test('-25.01 dBFS is degraded, not unavailable', () {
      final report = _build(events, noiseFloorDbfs: -25.01);
      expect(report.gateStatus, CapabilityStatus.degraded);
    });

    test('-25.0 dBFS is unavailable — backingTrackDominant boundary', () {
      final report = _build(events, noiseFloorDbfs: -25.0);
      expect(report.gateStatus, CapabilityStatus.unavailable);
      expect(
        report.gateReason,
        CapabilityUnavailableReason.backingTrackDominant,
      );
    });

    test('-24.99 dBFS is unavailable', () {
      final report = _build(events, noiseFloorDbfs: -24.99);
      expect(report.gateStatus, CapabilityStatus.unavailable);
      expect(
        report.gateReason,
        CapabilityUnavailableReason.backingTrackDominant,
      );
    });
  });

  group('a non-measured signal quality report fails closed', () {
    test('measured == false is unavailable(internalFailure)', () {
      final events = _events(
        List<double>.filled(10, 1.0),
        List<StrumDirection>.filled(10, StrumDirection.down),
      );
      final report = buildDynamicsMetrics(
        audio: _audio(events),
        events: events,
        signalQuality: _report(measured: false),
      );
      expect(report.gateStatus, CapabilityStatus.unavailable);
      expect(report.gateReason, CapabilityUnavailableReason.internalFailure);
    });
  });

  group(
    'target-gated accent accuracy (brief §6, ADR 0203 descriptive boundary)',
    () {
      test('without a target, accent accuracy is notApplicable', () {
        final events = _events(
          List<double>.filled(10, 1.0),
          List<StrumDirection>.filled(10, StrumDirection.down),
        );
        final report = _build(events);
        expect(
          _result(report, DynamicsMetricIds.accentAccuracy).status,
          CapabilityStatus.notApplicable,
        );
      });

      test('with a target, accent accuracy becomes available', () {
        final events = _events(
          List<double>.filled(10, 1.0),
          List<StrumDirection>.filled(10, StrumDirection.down),
        );
        final report = _build(events, expectedAccentEventIds: const <String>{});
        expect(
          _result(report, DynamicsMetricIds.accentAccuracy).status,
          CapabilityStatus.available,
        );
      });
    },
  );

  group('insufficient events fail closed', () {
    test('below the MetricGate minimum every metric is unavailable', () {
      final events = _events(
        List<double>.filled(3, 1.0),
        List<StrumDirection>.filled(3, StrumDirection.down),
      );
      final report = _build(events);
      for (final metric in report.metrics) {
        expect(metric.status, CapabilityStatus.unavailable);
        expect(
          metric.unavailableReason,
          CapabilityUnavailableReason.insufficientEvents,
        );
      }
    });
  });
}

double _value(DynamicsMetricReport report, String id) {
  final value = _result(report, id).value;
  return switch (value) {
    ScalarMetricValue(:final value) => value,
    PercentageMetricValue(:final value) => value,
    _ => throw StateError('no scalar/percentage value for $id'),
  };
}

AnalysisMetricResult _result(DynamicsMetricReport report, String id) =>
    report.metrics.firstWhere((metric) => metric.id == id);

DynamicsMetricReport _build(
  List<StrumEvent> events, {
  Set<String>? expectedAccentEventIds,
  double noiseFloorDbfs = -60.0,
  Set<int> clippedIndices = const <int>{},
  List<double> Function(List<double>)? canonicalOverride,
}) => buildDynamicsMetrics(
  audio: _audio(
    events,
    clippedIndices: clippedIndices,
    canonicalOverride: canonicalOverride,
  ),
  events: events,
  signalQuality: _report(noiseFloorDbfs: noiseFloorDbfs),
  expectedAccentEventIds: expectedAccentEventIds,
);

List<StrumEvent> _events(
  List<double> attackStrengths,
  List<StrumDirection> directions, {
  List<double>? localRms,
}) => <StrumEvent>[
  for (var i = 0; i < attackStrengths.length; i++)
    StrumEvent(
      id: 'e$i',
      time: Duration(milliseconds: _spacingMs * i),
      confidence: 1.0,
      direction: directions[i],
      sampleIndex: _spacingMs * i,
      attackStrength: attackStrengths[i],
      localRms: (localRms != null ? localRms[i] : attackStrengths[i] * 0.5),
      confidenceSource: EventConfidenceSources.heuristic,
    ),
];

/// Builds the raw original-sample buffer backing [events]. A clip pulse
/// (sample == 1.0, over the 0.999 threshold) is written into the middle of
/// event index i's 20 ms attack window whenever i is in [clippedIndices] —
/// the only channel [buildDynamicsMetrics] uses to derive the clipped flag.
PreprocessedAudio _audio(
  List<StrumEvent> events, {
  Set<int> clippedIndices = const <int>{},
  List<double> Function(List<double>)? canonicalOverride,
}) {
  final length = events.isEmpty
      ? _spacingMs
      : (events.last.sampleIndex! + _spacingMs);
  final samples = List<double>.filled(length, _quiet);
  for (var i = 0; i < events.length; i++) {
    if (clippedIndices.contains(i)) {
      samples[events[i].sampleIndex! + 10] = 1.0;
    }
  }
  return PreprocessedAudio(
    originalSamples: samples,
    canonicalSamples: canonicalOverride == null
        ? samples
        : canonicalOverride(samples),
    sampleRate: _sampleRate,
    originalChannelCount: 1,
    normalizationGain: 1.0,
    preprocessingVersion: 'test',
  );
}

SignalQualityReport _report({
  bool measured = true,
  double noiseFloorDbfs = -60.0,
  double silentRatio = 0.0,
}) => SignalQualityReport(
  overall: 1.0,
  peakDbfs: -1.0,
  rmsDbfs: -10.0,
  noiseFloorDbfs: noiseFloorDbfs,
  clippedSampleRatio: 0.0,
  silentRatio: silentRatio,
  tonalness: 1.0,
  measured: measured,
);
