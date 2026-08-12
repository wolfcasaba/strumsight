import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

const _beat = Duration(milliseconds: 500);
const _tolerance = Duration(milliseconds: 125);

void main() {
  group('buildTargetTimingMetrics — sign matrix', () {
    test('all early: negative bias, earlyRatio=1, lateRatio=0', () {
      final alignment = _alignmentOf(signedErrorsMs: List<int>.filled(8, -30));
      final results = _byId(
        buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
      );
      expect(_value(results[TimingMetricSuiteIds.target.signedBias]!), -30);
      expect(_value(results[TimingMetricSuiteIds.target.earlyRatio]!), 1.0);
      expect(_value(results[TimingMetricSuiteIds.target.lateRatio]!), 0.0);
    });

    test('all late: positive bias, lateRatio=1, earlyRatio=0', () {
      final alignment = _alignmentOf(signedErrorsMs: List<int>.filled(8, 30));
      final results = _byId(
        buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
      );
      expect(_value(results[TimingMetricSuiteIds.target.signedBias]!), 30);
      expect(_value(results[TimingMetricSuiteIds.target.earlyRatio]!), 0.0);
      expect(_value(results[TimingMetricSuiteIds.target.lateRatio]!), 1.0);
    });

    test(
      'alternating +/-30ms: bias ~= 0 but mean absolute error stays 30ms',
      () {
        final alignment = _alignmentOf(
          signedErrorsMs: <int>[
            for (var i = 0; i < 8; i++) i.isEven ? -30 : 30,
          ],
        );
        final results = _byId(
          buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
        );
        expect(
          _value(results[TimingMetricSuiteIds.target.signedBias]!).abs(),
          lessThanOrEqualTo(1e-9),
        );
        expect(
          _value(results[TimingMetricSuiteIds.target.meanAbsoluteError]!),
          30,
        );
      },
    );

    test('perfect: every error metric zero, onTimeRatio=1', () {
      final alignment = _alignmentOf(signedErrorsMs: List<int>.filled(8, 0));
      final results = _byId(
        buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
      );
      expect(
        _value(results[TimingMetricSuiteIds.target.meanAbsoluteError]!),
        0,
      );
      expect(
        _value(results[TimingMetricSuiteIds.target.medianAbsoluteError]!),
        0,
      );
      expect(_value(results[TimingMetricSuiteIds.target.p90AbsoluteError]!), 0);
      expect(_value(results[TimingMetricSuiteIds.target.signedBias]!), 0);
      expect(_value(results[TimingMetricSuiteIds.target.onTimeRatio]!), 1.0);
    });
  });

  group('buildTargetTimingMetrics — on-time threshold trio (120 BPM)', () {
    const aligner = EventAligner();
    const permissiveGate = MetricGate(
      minimumMatchedPairs: 1,
      minimumStreakMatchedPairs: 1,
    );

    test('124ms and 125ms are on-time (inclusive)', () {
      for (final deltaMs in const <int>[124, 125]) {
        final alignment = aligner.align(
          observed: <AnalysisEvent>[
            OnsetEvent(
              id: 'o',
              time: Duration(milliseconds: deltaMs),
              confidence: 1,
            ),
          ],
          expected: <ExpectedEvent>[
            ExpectedEvent(
              id: 'e',
              time: Duration.zero,
              type: ExpectedEventType.onset,
            ),
          ],
          beatDuration: _beat,
        );
        final results = _byId(
          buildTargetTimingMetrics(
            alignment: alignment,
            tolerance: const TolerancePolicy().forBeatDuration(_beat),
            gate: permissiveGate,
          ),
        );
        expect(
          _value(results[TimingMetricSuiteIds.target.onTimeRatio]!),
          1.0,
          reason: 'deltaMs=$deltaMs',
        );
      }
    });

    test('126ms neither matches nor counts on-time', () {
      final alignment = aligner.align(
        observed: <AnalysisEvent>[
          OnsetEvent(
            id: 'o',
            time: const Duration(milliseconds: 126),
            confidence: 1,
          ),
        ],
        expected: <ExpectedEvent>[
          ExpectedEvent(
            id: 'e',
            time: Duration.zero,
            type: ExpectedEventType.onset,
          ),
        ],
        beatDuration: _beat,
      );
      expect(alignment.matches, isEmpty);
      expect(alignment.missedExpected, hasLength(1));
      expect(alignment.extraObserved, hasLength(1));

      final results = _byId(
        buildTargetTimingMetrics(
          alignment: alignment,
          tolerance: const TolerancePolicy().forBeatDuration(_beat),
          gate: permissiveGate,
        ),
      );
      final onTime = results[TimingMetricSuiteIds.target.onTimeRatio]!;
      expect(onTime.status, CapabilityStatus.unavailable);
      expect(onTime.value, isNull);
    });
  });

  group('buildTargetTimingMetrics — p90 manual cell (OD-03)', () {
    test(
      'p90 pins the linear-interpolation value; differs from the median',
      () {
        const absErrorsMs = <int>[0, 10, 20, 30, 40, 50, 60, 70, 80, 900];
        final alignment = _alignmentOf(signedErrorsMs: absErrorsMs);
        final results = _byId(
          buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
        );
        final p90 = _value(
          results[TimingMetricSuiteIds.target.p90AbsoluteError]!,
        );
        final median = _value(
          results[TimingMetricSuiteIds.target.medianAbsoluteError]!,
        );
        expect(p90, closeTo(162, 1e-9));
        expect(median, closeTo(45, 1e-9));
        expect((p90 - median).abs(), greaterThan(50));
      },
    );
  });

  group('buildTargetTimingMetrics — minimum event count trio (OD-01)', () {
    test(
      '7 matched pairs is unavailable with a non-zero-implying null value',
      () {
        final alignment = _alignmentOf(signedErrorsMs: List<int>.filled(7, 0));
        final results = _byId(
          buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
        );
        final mae = results[TimingMetricSuiteIds.target.meanAbsoluteError]!;
        expect(mae.status, CapabilityStatus.unavailable);
        expect(
          mae.unavailableReason,
          CapabilityUnavailableReason.insufficientEvents,
        );
        expect(mae.value, isNull);
      },
    );

    test('8 matched pairs is available (inclusive)', () {
      final alignment = _alignmentOf(signedErrorsMs: List<int>.filled(8, 0));
      final results = _byId(
        buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
      );
      final mae = results[TimingMetricSuiteIds.target.meanAbsoluteError]!;
      expect(mae.status, CapabilityStatus.available);
      expect(mae.value, isNotNull);
    });

    test('9 matched pairs is available', () {
      final alignment = _alignmentOf(signedErrorsMs: List<int>.filled(9, 0));
      final results = _byId(
        buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
      );
      final mae = results[TimingMetricSuiteIds.target.meanAbsoluteError]!;
      expect(mae.status, CapabilityStatus.available);
    });
  });

  group('buildTargetTimingMetrics — streak matrix (OD-01)', () {
    test('[on,on,off,on,on,on] -> longest stable streak 3', () {
      final onTime = <bool>[true, true, false, true, true, true];
      final alignment = _alignmentOf(
        signedErrorsMs: [for (final on in onTime) on ? 0 : 500],
      );
      final results = _byId(
        buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
      );
      final streak = results[TimingMetricSuiteIds.target.longestStableStreak]!;
      expect(streak.status, CapabilityStatus.available);
      expect(_value(streak), 3);
    });

    test('all-off streak is a legitimate published zero, not unavailable', () {
      final alignment = _alignmentOf(signedErrorsMs: List<int>.filled(6, 500));
      final results = _byId(
        buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
      );
      final streak = results[TimingMetricSuiteIds.target.longestStableStreak]!;
      expect(streak.status, CapabilityStatus.available);
      expect(_value(streak), 0);
    });

    test('exactly 3 on-time pairs hits the streak minimum', () {
      final alignment = _alignmentOf(signedErrorsMs: List<int>.filled(3, 0));
      final results = _byId(
        buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
      );
      final streak = results[TimingMetricSuiteIds.target.longestStableStreak]!;
      expect(streak.status, CapabilityStatus.available);
      expect(_value(streak), 3);
    });

    test('below the streak minimum (2 pairs) is unavailable', () {
      final alignment = _alignmentOf(signedErrorsMs: List<int>.filled(2, 0));
      final results = _byId(
        buildTargetTimingMetrics(alignment: alignment, tolerance: _tolerance),
      );
      final streak = results[TimingMetricSuiteIds.target.longestStableStreak]!;
      expect(streak.status, CapabilityStatus.unavailable);
      expect(streak.value, isNull);
    });
  });

  group('buildTargetTimingMetrics — missed/extra ratios', () {
    test('10 expected + 8 observed, 7 matched: correct denominators', () {
      final matches = _matches(signedErrorsMs: List<int>.filled(7, 0));
      final alignment = AlignmentResult(
        matches: matches,
        missedExpected: <ExpectedEvent>[
          for (var i = 0; i < 3; i++)
            ExpectedEvent(
              id: 'missed-$i',
              time: Duration(milliseconds: 10000 + i),
              type: ExpectedEventType.onset,
            ),
        ],
        extraObserved: <AnalysisEvent>[
          OnsetEvent(
            id: 'extra-0',
            time: const Duration(milliseconds: 20000),
            confidence: 1,
          ),
        ],
        totalCost: 0,
        confidence: 1,
        diagnostics: _diagnostics(),
      );

      final results = _byId(
        buildTargetTimingMetrics(
          alignment: alignment,
          tolerance: _tolerance,
          gate: const MetricGate(minimumMatchedPairs: 7),
        ),
      );
      expect(
        _value(results[TimingMetricSuiteIds.target.missedRatio]!),
        closeTo(3 / 10, 1e-9),
      );
      expect(
        _value(results[TimingMetricSuiteIds.target.extraRatio]!),
        closeTo(1 / 8, 1e-9),
      );
    });
  });

  group('free-play timing — mode separation and confidence ceiling', () {
    test(
      'freeplay IDs are disjoint from target IDs and never appear together',
      () {
        final beatGrid = _beatGrid(beatCount: 10, confidence: 0.9);
        final observed = <AnalysisEvent>[
          for (var i = 0; i < 10; i++)
            OnsetEvent(
              id: 'o$i',
              time: Duration(milliseconds: 500 * i),
              confidence: 0.9,
            ),
        ];
        final freeplay = buildFreePlayTimingMetrics(
          observed: observed,
          beatGrid: beatGrid,
        );
        final freeplayIds = freeplay.map((r) => r.id).toSet();
        expect(
          freeplayIds.intersection(TimingMetricSuiteIds.target.all),
          isEmpty,
        );
        expect(freeplayIds, TimingMetricSuiteIds.freeplay.all);
      },
    );

    test(
      'freeplay confidence never exceeds the supporting beat grid confidence',
      () {
        const beatConfidence = 0.6;
        final beatGrid = _beatGrid(beatCount: 10, confidence: beatConfidence);
        final observed = <AnalysisEvent>[
          for (var i = 0; i < 10; i++)
            OnsetEvent(
              id: 'o$i',
              time: Duration(milliseconds: 500 * i),
              confidence: 1,
            ),
        ];
        final freeplay = buildFreePlayTimingMetrics(
          observed: observed,
          beatGrid: beatGrid,
        );
        for (final result in freeplay) {
          if (result.status == CapabilityStatus.available) {
            expect(
              result.confidence,
              lessThanOrEqualTo(beatConfidence + 1e-9),
              reason: result.id,
            );
          }
        }
      },
    );
  });
}

double _value(AnalysisMetricResult result) => switch (result.value) {
  ScalarMetricValue(:final value) => value,
  PercentageMetricValue(:final value) => value,
  _ => throw StateError('unexpected metric value type for ${result.id}'),
};

Map<String, AnalysisMetricResult> _byId(List<AnalysisMetricResult> results) => {
  for (final r in results) r.id: r,
};

AlignmentDiagnostics _diagnostics() => const AlignmentDiagnostics(
  algorithmVersion: 'test',
  observedCount: 0,
  expectedCount: 0,
  candidatePairCount: 0,
  maximumCandidateBandWidth: 0,
  scoreStateCount: 0,
);

List<AlignmentMatch> _matches({required List<int> signedErrorsMs}) => [
  for (var i = 0; i < signedErrorsMs.length; i++)
    AlignmentMatch(
      observedIndex: i,
      expectedIndex: i,
      observed: OnsetEvent(
        id: 'o$i',
        time: Duration(milliseconds: 100000 + i * 1000 + signedErrorsMs[i]),
        confidence: 1,
      ),
      expected: ExpectedEvent(
        id: 'e$i',
        time: Duration(milliseconds: 100000 + i * 1000),
        type: ExpectedEventType.onset,
      ),
      timingError: Duration(milliseconds: signedErrorsMs[i]),
      cost: 0,
    ),
];

AlignmentResult _alignmentOf({required List<int> signedErrorsMs}) =>
    AlignmentResult(
      matches: _matches(signedErrorsMs: signedErrorsMs),
      missedExpected: const <ExpectedEvent>[],
      extraObserved: const <AnalysisEvent>[],
      totalCost: 0,
      confidence: 1,
      diagnostics: _diagnostics(),
    );

BeatGrid _beatGrid({required int beatCount, required double confidence}) =>
    BeatGrid(
      beats: <BeatPoint>[
        for (var i = 0; i < beatCount; i++)
          BeatPoint(
            index: i,
            time: Duration(milliseconds: 500 * i),
            confidence: confidence,
            source: BeatSource.estimated,
          ),
      ],
      bars: const <BarPoint>[],
      beatsPerBar: 4,
      beatsPerBarSource: BeatsPerBarSource.legacyDefault,
      status: CapabilityStatus.available,
      meterStatus: CapabilityStatus.notApplicable,
    );
