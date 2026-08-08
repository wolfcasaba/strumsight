/// Configurable audio–vision synchronization quality buckets.
library;

/// Alignment quality consumed by the picking-metric contract in E05-R19.
///
/// `poor` and `acceptable` are not suitable for event-level conclusions;
/// `good` and `excellent` are. The numeric defaults are provisional until the
/// pending device benchmark can tune them without changing this contract.
enum SyncQuality { poor, acceptable, good, excellent }

/// Benchmark-configurable absolute alignment-error limits, in microseconds.
final class SyncQualityThresholds {
  const SyncQualityThresholds({
    this.excellentMaximumErrorUs = 10_000,
    this.goodMaximumErrorUs = 25_000,
    this.acceptableMaximumErrorUs = 50_000,
  }) : assert(excellentMaximumErrorUs >= 0),
       assert(goodMaximumErrorUs > excellentMaximumErrorUs),
       assert(acceptableMaximumErrorUs > goodMaximumErrorUs);

  /// The highest absolute error that is excellent.
  final int excellentMaximumErrorUs;

  /// The highest absolute error that is good.
  final int goodMaximumErrorUs;

  /// The highest absolute error that is acceptable.
  final int acceptableMaximumErrorUs;

  SyncQuality forAbsoluteErrorUs(int errorUs) {
    final absoluteErrorUs = errorUs.abs();
    if (absoluteErrorUs <= excellentMaximumErrorUs) {
      return SyncQuality.excellent;
    }
    if (absoluteErrorUs <= goodMaximumErrorUs) return SyncQuality.good;
    if (absoluteErrorUs <= acceptableMaximumErrorUs) {
      return SyncQuality.acceptable;
    }
    return SyncQuality.poor;
  }

  bool isEventLevelReliable(SyncQuality quality) =>
      quality == SyncQuality.good || quality == SyncQuality.excellent;
}
