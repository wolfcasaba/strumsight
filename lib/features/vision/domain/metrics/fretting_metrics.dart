import 'fretting_metric_engine.dart';
import 'metric_definition.dart';

/// The complete, validated production proxy-metric catalog.
abstract final class FrettingMetrics {
  static const ids = FrettingMetricId.values;

  static List<MetricDefinition> get definitions => frettingMetricDefinitions;

  static bool get isValid =>
      definitions.length == ids.length &&
      definitions.every((definition) => definition.isValid);
}
