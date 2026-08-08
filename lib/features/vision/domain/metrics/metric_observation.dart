import 'package:meta/meta.dart';

enum MetricObservability { observable, notObservable }

@immutable
final class MetricObservation {
  const MetricObservation._({
    required this.observability,
    required this.value,
    required this.confidence,
  });

  factory MetricObservation.observable({
    required double value,
    required double confidence,
  }) {
    if (!value.isFinite) {
      return MetricObservation.notObservable();
    }
    if (!(confidence.isFinite && confidence >= 0 && confidence <= 1)) {
      return MetricObservation.notObservable();
    }
    return MetricObservation._(
      observability: MetricObservability.observable,
      value: value,
      confidence: confidence,
    );
  }

  factory MetricObservation.notObservable() => const MetricObservation._(
    observability: MetricObservability.notObservable,
    value: null,
    confidence: 0,
  );

  final MetricObservability observability;
  final double? value;
  final double confidence;

  bool get isObservable => observability == MetricObservability.observable;
}
