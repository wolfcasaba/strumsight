import '../../domain/analysis_capability.dart';
import '../../domain/signal_quality_report.dart';

/// Fail-closed dynamics quality-gate verdict (ADR 0234 §3).
///
/// [reason] is only present when [status] is [CapabilityStatus.unavailable];
/// a [status] of `degraded` or `available` never needs one.
final class DynamicsGateResult {
  DynamicsGateResult({required this.status, this.reason}) {
    if (status == CapabilityStatus.unavailable && reason == null) {
      throw ArgumentError('Unavailable dynamics gate requires a reason.');
    }
    if (status != CapabilityStatus.unavailable && reason != null) {
      throw ArgumentError('Only an unavailable gate carries a reason.');
    }
  }

  final CapabilityStatus status;
  final CapabilityUnavailableReason? reason;
}

/// Quality gate that blocks or degrades dynamics publication before any
/// value is computed (ADR 0234, brief §5.4, OD-03).
///
/// A non-[SignalQualityReport.measured] report is fail-closed
/// [CapabilityStatus.unavailable] — never treated as a neutral zero. The
/// noise-floor bands are a provisional backing-track *proxy*, not source
/// identification (SDD §11.5); the thresholds are named constants pending
/// R29 calibration.
final class DynamicsGate {
  DynamicsGate({
    this.clippedEventRatioDegraded = 0.0,
    this.clippedEventRatioUnavailable = 0.05,
    this.noiseFloorDegradedDbfs = -35.0,
    this.noiseFloorUnavailableDbfs = -25.0,
    this.silentRatioUnavailable = 0.95,
  }) {
    if (!clippedEventRatioDegraded.isFinite ||
        clippedEventRatioDegraded < 0 ||
        clippedEventRatioDegraded > 1) {
      throw ArgumentError.value(
        clippedEventRatioDegraded,
        'clippedEventRatioDegraded',
        'must be finite and in [0, 1]',
      );
    }
    if (!clippedEventRatioUnavailable.isFinite ||
        clippedEventRatioUnavailable < 0 ||
        clippedEventRatioUnavailable > 1) {
      throw ArgumentError.value(
        clippedEventRatioUnavailable,
        'clippedEventRatioUnavailable',
        'must be finite and in [0, 1]',
      );
    }
    if (clippedEventRatioUnavailable < clippedEventRatioDegraded) {
      throw ArgumentError(
        'clippedEventRatioUnavailable must be >= clippedEventRatioDegraded.',
      );
    }
    if (!noiseFloorDegradedDbfs.isFinite) {
      throw ArgumentError.value(
        noiseFloorDegradedDbfs,
        'noiseFloorDegradedDbfs',
        'must be finite',
      );
    }
    if (!noiseFloorUnavailableDbfs.isFinite) {
      throw ArgumentError.value(
        noiseFloorUnavailableDbfs,
        'noiseFloorUnavailableDbfs',
        'must be finite',
      );
    }
    if (noiseFloorUnavailableDbfs < noiseFloorDegradedDbfs) {
      throw ArgumentError(
        'noiseFloorUnavailableDbfs must be >= noiseFloorDegradedDbfs.',
      );
    }
    if (!silentRatioUnavailable.isFinite ||
        silentRatioUnavailable < 0 ||
        silentRatioUnavailable > 1) {
      throw ArgumentError.value(
        silentRatioUnavailable,
        'silentRatioUnavailable',
        'must be finite and in [0, 1]',
      );
    }
  }

  /// Above this ratio (exclusive) the dynamics metrics degrade — clipping is
  /// present but does not yet dominate the take.
  final double clippedEventRatioDegraded;

  /// Above this ratio (exclusive) — inclusive at exactly this value stays
  /// `degraded` — dynamics publication is blocked with `inputClipped`.
  final double clippedEventRatioUnavailable;

  /// At or above this noise floor (inclusive) the take degrades — the
  /// backing-track-dominance proxy (OD-03).
  final double noiseFloorDegradedDbfs;

  /// At or above this noise floor (inclusive) dynamics is blocked with
  /// `backingTrackDominant`.
  final double noiseFloorUnavailableDbfs;

  /// At or above this silent-sample ratio the take is too quiet to trust —
  /// blocked with `inputTooNoisy`.
  final double silentRatioUnavailable;

  DynamicsGateResult evaluate({
    required SignalQualityReport report,
    required double clippedEventRatio,
  }) {
    if (!clippedEventRatio.isFinite || clippedEventRatio < 0) {
      throw ArgumentError.value(clippedEventRatio, 'clippedEventRatio');
    }
    if (!report.measured) {
      return DynamicsGateResult(
        status: CapabilityStatus.unavailable,
        reason: CapabilityUnavailableReason.internalFailure,
      );
    }
    // SignalQualityReport only range-checks silentRatio/noiseFloorDbfs
    // (`< 0 || > 1`), and every comparison against NaN is false — so a
    // non-finite value would otherwise slide through every threshold below
    // as if it were within range and publish as available (security review
    // R16 MAJOR-2). Fail closed instead.
    if (!report.noiseFloorDbfs.isFinite || !report.silentRatio.isFinite) {
      return DynamicsGateResult(
        status: CapabilityStatus.unavailable,
        reason: CapabilityUnavailableReason.internalFailure,
      );
    }
    if (report.noiseFloorDbfs >= noiseFloorUnavailableDbfs) {
      return DynamicsGateResult(
        status: CapabilityStatus.unavailable,
        reason: CapabilityUnavailableReason.backingTrackDominant,
      );
    }
    if (clippedEventRatio > clippedEventRatioUnavailable) {
      return DynamicsGateResult(
        status: CapabilityStatus.unavailable,
        reason: CapabilityUnavailableReason.inputClipped,
      );
    }
    if (report.silentRatio >= silentRatioUnavailable) {
      return DynamicsGateResult(
        status: CapabilityStatus.unavailable,
        reason: CapabilityUnavailableReason.inputTooNoisy,
      );
    }
    final degraded =
        report.noiseFloorDbfs >= noiseFloorDegradedDbfs ||
        clippedEventRatio > clippedEventRatioDegraded;
    return DynamicsGateResult(
      status: degraded ? CapabilityStatus.degraded : CapabilityStatus.available,
    );
  }
}
