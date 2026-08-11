import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  test('catalog IDs are unique and have stable namespace.name.vN form', () {
    const expression = r'^[a-z_]+\.[a-z0-9_]+\.v[0-9]+$';
    final pattern = RegExp(expression);
    expect(
      AnalysisMetricId.known.length,
      equals(AnalysisMetricId.known.toSet().length),
    );
    expect(AnalysisMetricId.known, everyElement(matches(pattern)));
  });

  test(
    'sealed metric values support an exhaustive switch without a default',
    () {
      final values = <AnalysisMetricValue>[
        ScalarMetricValue(1),
        PercentageMetricValue(1),
        DurationMetricValue(Duration.zero),
        DistributionMetricValue(const <double>[1]),
        TimeSeriesMetricValue(const <MetricTimePoint>[]),
        CategoryMetricValue('steady'),
        ScoreMetricValue(100),
      ];
      for (final value in values) {
        final name = switch (value) {
          ScalarMetricValue() => 'scalar',
          PercentageMetricValue() => 'percentage',
          DurationMetricValue() => 'duration',
          DistributionMetricValue() => 'distribution',
          TimeSeriesMetricValue() => 'series',
          CategoryMetricValue() => 'category',
          ScoreMetricValue() => 'score',
        };
        expect(name, isNotEmpty);
      }
    },
  );

  test('metric results reject IDs outside the catalog', () {
    expect(
      () => AnalysisMetricResult(
        id: 'timing.made_up.v1',
        version: 1,
        status: CapabilityStatus.available,
        confidence: 1,
        value: ScalarMetricValue(1),
        unit: 'unit',
        sampleCount: 1,
        evidence: const <String>[],
      ),
      throwsArgumentError,
    );
  });
}
