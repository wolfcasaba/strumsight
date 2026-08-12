import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  group('buildRhythmMetrics — consistency and publication boundary', () {
    test('uniform eighths publish the complete target suite', () {
      final report = buildRhythmMetrics(
        events: _events(const <int>[
          0,
          500,
          1000,
          1500,
          2000,
          2500,
          3000,
          3500,
        ]),
        beatGrid: _targetGrid(),
      );

      expect(
        report.metrics.map((result) => result.id).toSet(),
        RhythmMetricSuiteIds.target.all,
      );
      expect(report.metrics, everyElement(isA<AnalysisMetricResult>()));
    });

    test(
      'irregular and accelerating patterns retain a complete finite suite',
      () {
        for (final fixture in <List<int>>[
          const <int>[0, 300, 1100, 1450, 2400, 3000, 3900, 4150],
          const <int>[0, 800, 1500, 2100, 2600, 3000, 3300, 3500],
        ]) {
          final report = buildRhythmMetrics(
            events: _events(fixture),
            beatGrid: _targetGrid(),
          );
          expect(
            report.metrics.map((result) => result.id).toSet(),
            RhythmMetricSuiteIds.target.all,
          );
          for (final result in report.metrics) {
            expect(result.status, isNot(CapabilityStatus.unavailable));
            expect(result.value, isNotNull, reason: result.id);
          }
        }
      },
    );

    test('perfectly even IOIs publish consistency one', () {
      final report = buildRhythmMetrics(
        events: _events(const <int>[0, 100, 200, 300, 400, 500, 600, 700]),
        beatGrid: _targetGrid(),
      );

      expect(
        _value(report.metrics, RhythmMetricSuiteIds.target.ioiConsistency),
        1.0,
      );
    });

    test('median-based CV fixture publishes 0.9 at exact CV 0.1', () {
      // python3 -c 'import math; v=[90,90,110,110]; print(math.sqrt(sum((x-sum(v)/len(v))**2 for x in v)/len(v))/100)'
      // -> 0.1. The median IOI is 100, not the mean selected by an
      // accidentally mean-based implementation.
      final report = buildRhythmMetrics(
        events: _fromIois(const <int>[90, 90, 110, 110, 90, 90, 110, 110]),
        beatGrid: _targetGrid(),
      );

      expect(
        _value(report.metrics, RhythmMetricSuiteIds.target.ioiConsistency),
        closeTo(0.9, 1e-9),
      );
    });

    test('median-based CV fixture publishes 0.5 at exact CV 0.5', () {
      // python3 -c 'import math; v=[50,50,150,150]; print(math.sqrt(sum((x-sum(v)/len(v))**2 for x in v)/len(v))/100)'
      // -> 0.5, with a median IOI of 100.
      final report = buildRhythmMetrics(
        events: _fromIois(const <int>[50, 50, 150, 150, 50, 50, 150, 150]),
        beatGrid: _targetGrid(),
      );

      expect(
        _value(report.metrics, RhythmMetricSuiteIds.target.ioiConsistency),
        closeTo(0.5, 1e-9),
      );
    });

    test('target swing ratio is measured as two to one', () {
      final report = buildRhythmMetrics(
        events: _fromIois(const <int>[667, 333, 667, 333, 667, 333, 667, 333]),
        beatGrid: _targetGrid(),
      );

      expect(report.swingStatus, CapabilityStatus.available);
      expect(
        _value(report.metrics, RhythmMetricSuiteIds.target.swingRatio!),
        closeTo(2, 0.05),
      );
    });

    test(
      'inferred rhythm never publishes swing and exposes not applicable',
      () {
        final report = buildRhythmMetrics(
          events: _events(const <int>[
            0,
            500,
            1000,
            1500,
            2000,
            2500,
            3000,
            3500,
          ]),
          beatGrid: _inferredGrid(),
        );

        expect(report.swingStatus, CapabilityStatus.notApplicable);
        expect(
          report.metrics.map((result) => result.id),
          isNot(contains(AnalysisMetricId.rhythmTargetSwingRatio)),
        );
        expect(
          report.metrics.map((result) => result.id).toSet(),
          RhythmMetricSuiteIds.inferred.all,
        );
      },
    );

    test(
      'inferred confidences do not exceed the mean used beat confidence',
      () {
        const gridConfidence = 0.4;
        final report = buildRhythmMetrics(
          events: _events(const <int>[
            0,
            500,
            1000,
            1500,
            2000,
            2500,
            3000,
            3500,
          ]),
          beatGrid: _inferredGrid(confidence: gridConfidence),
        );

        for (final result in report.metrics) {
          expect(
            result.confidence,
            lessThanOrEqualTo(gridConfidence + 1e-9),
            reason: result.id,
          );
        }
      },
    );

    test('fewer than the reused MetricGate minimum events are unavailable', () {
      final report = buildRhythmMetrics(
        events: _events(const <int>[0, 100, 200, 300, 400, 500, 600]),
        beatGrid: _targetGrid(),
      );

      for (final result in report.metrics) {
        expect(result.status, CapabilityStatus.unavailable, reason: result.id);
        expect(
          result.unavailableReason,
          CapabilityUnavailableReason.insufficientEvents,
        );
        expect(result.value, isNull);
      }
    });
  });
}

double _value(List<AnalysisMetricResult> results, String id) {
  final result = results.singleWhere((result) => result.id == id);
  return switch (result.value) {
    ScalarMetricValue(:final value) => value,
    PercentageMetricValue(:final value) => value,
    _ => throw StateError('Unexpected value for $id'),
  };
}

List<AnalysisEvent> _fromIois(List<int> iois) {
  var time = 0;
  return _events(<int>[0, for (final ioi in iois) time += ioi]);
}

List<AnalysisEvent> _events(List<int> milliseconds) => <AnalysisEvent>[
  for (var index = 0; index < milliseconds.length; index++)
    OnsetEvent(
      id: 'event-$index',
      time: Duration(milliseconds: milliseconds[index]),
      confidence: 1,
    ),
];

BeatGrid _targetGrid() => _grid(
  source: BeatSource.target,
  beatsPerBarSource: BeatsPerBarSource.target,
);

BeatGrid _inferredGrid({double confidence = 1}) => _grid(
  source: BeatSource.estimated,
  beatsPerBarSource: BeatsPerBarSource.legacyDefault,
  confidence: confidence,
);

BeatGrid _grid({
  required BeatSource source,
  required BeatsPerBarSource beatsPerBarSource,
  double confidence = 1,
}) => BeatGrid(
  beats: <BeatPoint>[
    for (var index = 0; index < 9; index++)
      BeatPoint(
        index: index,
        time: Duration(milliseconds: index * 1000),
        confidence: confidence,
        source: source,
      ),
  ],
  bars: const <BarPoint>[],
  beatsPerBar: 4,
  beatsPerBarSource: beatsPerBarSource,
  status: CapabilityStatus.available,
  meterStatus: beatsPerBarSource == BeatsPerBarSource.target
      ? CapabilityStatus.available
      : CapabilityStatus.notApplicable,
);
