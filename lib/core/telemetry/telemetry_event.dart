/// Privacy-safe telemetry event contract (ADR 0484 D1, SDD Ch12 §5.1).
///
/// The prohibition on carrying raw user content is STRUCTURAL, not a filter
/// applied afterwards: [TelemetryEvent] has no field a raw prompt, an audio
/// clip, an image or free user text could be placed into. Every field is
/// either a closed enum or a bounded count. There is no
/// `Map<String, dynamic>` / `dynamic` / `Object?` payload field, and no free
/// `String` field — a redactor is the SECOND line of defence, never the
/// first, because a filter can be incomplete and a field that does not exist
/// cannot leak.
library;

/// The closed catalogue of event names a [TelemetryEvent] may report.
///
/// See `docs/analytics/event-catalog.md` for the human-readable description
/// of each value — that document must stay in sync with this enum.
enum TelemetryEventName {
  appLaunched,
  screenViewed,
  chordDetectionCompleted,
  strumDirectionDetected,
  tunerSessionCompleted,
  practiceSessionCompleted,
  tutorTurnCompleted,
  settingsChanged,
  diagnosticsUploadAttempted,
}

/// The closed grouping [TelemetryEventName] values belong to — used by the
/// release dashboard to roll events up without inventing a second taxonomy.
enum TelemetryEventCategory {
  lifecycle,
  detection,
  session,
  tutor,
  settings,
  diagnostics,
}

/// The outcome of the operation an event reports. `unknown` exists for the
/// rare case an operation's own outcome could not be determined (e.g. the
/// process was torn down mid-operation) — it is a event-level result, not
/// the release-dashboard `unknown` verdict of `docs/operations/slo.yaml`
/// (ADR 0484 D3), which is a separate, machine-checked concept.
enum TelemetryOperationResult { success, failure, cancelled, unknown }

/// A capability the reporting operation ran under. Closed on purpose: a free
/// "which model/version" string would reopen exactly the free-text hole D1
/// closes.
enum TelemetryCapability { onDeviceMl, onDeviceDsp, cloudTutor, cloudSync }

/// A time span expressed as a bucket, never as a raw millisecond count
/// (ADR 0484 D1 / SDD Ch12 §6 A4) — a raw duration is a de-facto free-form
/// channel (e.g. it can encode a timestamp difference that correlates to
/// other logs), and buckets are all the release SLOs in
/// `docs/operations/slo.yaml` ever need.
///
/// Boundaries are INCLUSIVE on the lower edge: `[0,250) [250,500) [500,1000)
/// [1000,3000) [3000,10000) [10000,∞)`.
enum TelemetryDurationBucket {
  ms0To250(upperExclusiveMs: 250),
  ms250To500(upperExclusiveMs: 500),
  ms500To1000(upperExclusiveMs: 1000),
  ms1000To3000(upperExclusiveMs: 3000),
  ms3000To10000(upperExclusiveMs: 10000),
  ms10000AndAbove(upperExclusiveMs: null);

  const TelemetryDurationBucket({required this.upperExclusiveMs});

  /// The bucket's exclusive upper bound in milliseconds, or `null` for the
  /// unbounded top bucket.
  final int? upperExclusiveMs;

  /// Maps a measured duration to its bucket. [milliseconds] must be `>= 0`.
  static TelemetryDurationBucket fromMilliseconds(int milliseconds) {
    if (milliseconds < 0) {
      throw ArgumentError.value(milliseconds, 'milliseconds', 'must be >= 0');
    }
    for (final bucket in TelemetryDurationBucket.values) {
      final upper = bucket.upperExclusiveMs;
      if (upper == null || milliseconds < upper) return bucket;
    }
    return TelemetryDurationBucket.ms10000AndAbove;
  }
}

/// One privacy-safe telemetry event.
///
/// Every field is a closed enum — there is no field a raw prompt, an
/// audio/video sample or free user text could occupy (ADR 0484 D1).
final class TelemetryEvent {
  const TelemetryEvent({
    required this.name,
    required this.category,
    required this.result,
    required this.durationBucket,
    this.capability,
  });

  final TelemetryEventName name;
  final TelemetryEventCategory category;
  final TelemetryOperationResult result;
  final TelemetryDurationBucket durationBucket;
  final TelemetryCapability? capability;
}
