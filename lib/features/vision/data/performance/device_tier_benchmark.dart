import 'package:strumsight/features/vision/domain/performance/vision_device_tier.dart';

/// One aggregate measurement supplied by a future benchmark runner.
final class DeviceTierBenchmarkMeasurement {
  const DeviceTierBenchmarkMeasurement({
    required this.averageFrameProcessingTimeMs,
  });

  final int averageFrameProcessingTimeMs;
}

/// Self-contained outcome that represents an unsupported benchmark safely.
final class DeviceTierBenchmarkResult {
  const DeviceTierBenchmarkResult.available(this.classification)
    : isAvailable = true,
      unavailableReason = null;

  const DeviceTierBenchmarkResult.unavailable(this.unavailableReason)
    : classification = null,
      isAvailable = false;

  final VisionDeviceTierClassification? classification;
  final bool isAvailable;
  final String? unavailableReason;
}

/// Translates benchmark samples to the deterministic domain classifier.
final class DeviceTierBenchmark {
  const DeviceTierBenchmark({
    this.classifier = const VisionDeviceTierClassifier(),
  });

  final VisionDeviceTierClassifier classifier;

  DeviceTierBenchmarkResult evaluate(
    DeviceTierBenchmarkMeasurement measurement,
  ) {
    try {
      return DeviceTierBenchmarkResult.available(
        classifier.classify(
          VisionDeviceTierBenchmarkInput(
            measurement.averageFrameProcessingTimeMs,
          ),
        ),
      );
    } on ArgumentError {
      return const DeviceTierBenchmarkResult.unavailable(
        'invalid-frame-processing-time',
      );
    }
  }
}
