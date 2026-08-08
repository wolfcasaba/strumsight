import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/metrics/fretting_metrics.dart';
import 'package:strumsight/features/vision/domain/metrics/metric_observation.dart';

void main() {
  test('every catalog definition has a complete contract', () {
    expect(FrettingMetrics.definitions, hasLength(6));
    for (final definition in FrettingMetrics.definitions) {
      expect(definition.isValid, isTrue);
      expect(definition.confidenceFormula, isNotEmpty);
      expect(definition.requiredCapability, isNotNull);
    }
  });

  test('observation rejects non-finite values and exposes no estimate', () {
    final observation = MetricObservation.observable(
      value: double.nan,
      confidence: 1,
    );
    expect(observation.isObservable, isFalse);
    expect(observation.value, isNull);
    expect(observation.confidence, 0);
  });
}
