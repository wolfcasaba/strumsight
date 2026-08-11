import 'analysis_capability.dart';
import 'analysis_metric_catalog.dart';

/// Closed set of metric payloads; untyped [Object] metric values are forbidden.
sealed class AnalysisMetricValue {
  const AnalysisMetricValue();
}

final class ScalarMetricValue extends AnalysisMetricValue {
  ScalarMetricValue(this.value) {
    if (!value.isFinite) throw ArgumentError.value(value, 'value');
  }
  final double value;
}

final class PercentageMetricValue extends AnalysisMetricValue {
  PercentageMetricValue(this.value) {
    if (value < 0 || value > 1) {
      throw ArgumentError.value(value, 'value', 'must be in [0, 1]');
    }
  }
  final double value;
}

final class DurationMetricValue extends AnalysisMetricValue {
  DurationMetricValue(this.value) {
    if (value.isNegative) {
      throw ArgumentError.value(value, 'value');
    }
  }
  final Duration value;
}

final class DistributionMetricValue extends AnalysisMetricValue {
  DistributionMetricValue(List<double> values)
    : values = List<double>.unmodifiable(values) {
    if (this.values.any((value) => !value.isFinite)) {
      throw ArgumentError('Distribution values must be finite.');
    }
  }
  final List<double> values;
}

final class MetricTimePoint {
  MetricTimePoint({required this.time, required this.value}) {
    if (time.isNegative || !value.isFinite) {
      throw ArgumentError('Invalid metric time point.');
    }
  }
  final Duration time;
  final double value;
}

final class TimeSeriesMetricValue extends AnalysisMetricValue {
  TimeSeriesMetricValue(List<MetricTimePoint> points)
    : points = List<MetricTimePoint>.unmodifiable(points);
  final List<MetricTimePoint> points;
}

final class CategoryMetricValue extends AnalysisMetricValue {
  CategoryMetricValue(this.value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'value');
    }
  }
  final String value;
}

final class ScoreMetricValue extends AnalysisMetricValue {
  ScoreMetricValue(this.value) {
    if (value < 0 || value > 100) {
      throw ArgumentError.value(value, 'value', 'must be in 0..100');
    }
  }
  final double value;
}

/// Metric publication record. `null` value is an explicit unavailable state,
/// never a synthetic zero.
final class AnalysisMetricResult {
  AnalysisMetricResult({
    required this.id,
    required this.version,
    required this.status,
    required this.confidence,
    required this.unit,
    required this.sampleCount,
    required List<String> evidence,
    this.value,
    this.unavailableReason,
  }) : evidence = List<String>.unmodifiable(evidence) {
    if (!AnalysisMetricId.contains(id)) {
      throw ArgumentError.value(id, 'id', 'must be from AnalysisMetricId');
    }
    if (version < 1 || !id.endsWith('.v$version')) {
      throw ArgumentError.value(version, 'version');
    }
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence');
    }
    if (sampleCount < 0) {
      throw ArgumentError.value(sampleCount, 'sampleCount');
    }
    if (unit.trim().isEmpty) {
      throw ArgumentError.value(unit, 'unit');
    }
    if ((status == CapabilityStatus.available ||
            status == CapabilityStatus.degraded) &&
        value == null) {
      throw ArgumentError('Published metrics require a value.');
    }
    if (status == CapabilityStatus.unavailable && unavailableReason == null) {
      throw ArgumentError('Unavailable metrics require an explanation.');
    }
  }

  final String id;
  final int version;
  final CapabilityStatus status;
  final double confidence;
  final AnalysisMetricValue? value;
  final String unit;
  final int sampleCount;
  final List<String> evidence;
  final CapabilityUnavailableReason? unavailableReason;
}
