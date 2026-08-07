// E05-R12 — Hand landmark domain (ADR 0180 §Döntés 3, ADR 0185 §Döntés 4).
//
// Stabil StrumSight landmark ID-k (21 pont/kéz) — a domain NEM függ provider-
// API-tól. A `data/landmarks/` adapterek a saját provider-outputjukat
// (pl. MediaPipe Hands TFLite tömbindexeit) itt, ebben a domainben
// CANONICAL StrumSight ID-kre képzik le. A hívó kizárólag ezen az
// enumon kérdez le — soha ne provider-indexet.
//
// Zero-hand output `notObservable`, NEM failure, NEM nullákkal töltött
// álkimenet (brief §5.2). A provider-oldali mapping bármelyik ujj
// hiányzó ízületét `null`-ként hagyja (a `byId` accessor így adja vissza).

library;

/// The 21 stable, provider-independent landmark IDs for a single hand.
///
/// Canonical order follows the publicly documented MediaPipe Hands topology:
/// `wrist`, then thumb (cmc, mcp, ip, tip), index/middle/ring/pinky
/// (mcp, pip, dip, tip) — but the domain value names are StrumSight's,
/// not provider indices. See ADR 0185 §Döntés 4.
enum HandLandmarkId {
  wrist,
  thumbCmc,
  thumbMcp,
  thumbIp,
  thumbTip,
  indexMcp,
  indexPip,
  indexDip,
  indexTip,
  middleMcp,
  middlePip,
  middleDip,
  middleTip,
  ringMcp,
  ringPip,
  ringDip,
  ringTip,
  pinkyMcp,
  pinkyPip,
  pinkyDip,
  pinkyTip,
}

/// Which physical hand the observation describes.
///
/// Mapping to a guitar role (`frettingHand`/`pickingHand`) is the caller's
/// responsibility — handedness and guitar role are independent concepts
/// (SDD §15.3).
enum Handedness { left, right }

/// One landmark point in the model's non-mirrored, resolution-independent
/// normalized frame space.
///
/// `x` and `y` are normalized to `[0, 1]`; `z` is a relative depth
/// (provider-specific unit, sign convention provider-specific but stable per
/// provider); `visibility` ∈ `[0, 1]` is the provider's self-reported
/// confidence that the point is actually visible (vs. extrapolated).
final class HandLandmarkPoint {
  HandLandmarkPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  }) {
    if (!(x.isFinite && y.isFinite && z.isFinite)) {
      throw ArgumentError('HandLandmarkPoint coordinates must be finite');
    }
    if (!(visibility >= 0 && visibility <= 1)) {
      throw ArgumentError.value(visibility, 'visibility', 'Must be in [0, 1].');
    }
  }

  final double x;
  final double y;
  final double z;
  final double visibility;

  @override
  bool operator ==(Object other) =>
      other is HandLandmarkPoint &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.visibility == visibility;

  @override
  int get hashCode => Object.hash(x, y, z, visibility);
}

/// One detected hand. The `landmarks` map carries exactly the IDs the
/// provider was able to localize — missing IDs are absent, never
/// zero-filled (brief §5.2).
final class HandObservation {
  HandObservation({
    required this.handedness,
    required Map<HandLandmarkId, HandLandmarkPoint> landmarks,
    required this.confidence,
  }) : _landmarks = Map.unmodifiable(landmarks) {
    if (!(confidence.isFinite && confidence >= 0 && confidence <= 1)) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'Must be a finite number in [0, 1].',
      );
    }
  }

  final Handedness handedness;

  final Map<HandLandmarkId, HandLandmarkPoint> _landmarks;

  /// Overall hand-detection confidence in `[0, 1]`.
  final double confidence;

  /// Returns the landmark for the given stable StrumSight ID, or `null` if
  /// the provider did not localize it for this hand.
  ///
  /// This is the SOLE accessor — domain callers must NOT use provider
  /// indices. Use `HandLandmarkId.values` to enumerate the full topology.
  HandLandmarkPoint? byId(HandLandmarkId id) => _landmarks[id];

  /// Number of landmarks present for this hand.
  int get count => _landmarks.length;
}

/// How many hands the provider actually observed.
///
/// `notObservable` is the explicit "we cannot tell" signal — it is NOT a
/// failure (brief §5.2). Callers distinguish the three cases instead of
/// reading list length.
enum HandLandmarkObservability { notObservable, one, two }

/// The complete output of one `HandLandmarkProvider.infer` call.
///
/// `timestampUs` carries the monotonic microseconds-since-session-start
/// timestamp of the source `VisionImage` (the provider MUST propagate it
/// unchanged). Out-of-order timestamps are filtered by a
/// `MonotonicHandLandmarkProvider` wrapper, not by the provider itself.
final class HandLandmarkResult {
  HandLandmarkResult({
    required this.timestampUs,
    required this.observability,
    required List<HandObservation> hands,
  }) : assert(timestampUs >= 0, 'timestampUs must be non-negative'),
       _hands = List.unmodifiable(hands);

  /// Convenience constructor for tests and adapters that have no hand
  /// landmarks to attach but know the observability directly.
  factory HandLandmarkResult.empty({
    required int timestampUs,
    required HandLandmarkObservability observability,
  }) => HandLandmarkResult(
    timestampUs: timestampUs,
    observability: observability,
    hands: const <HandObservation>[],
  );

  final int timestampUs;
  final HandLandmarkObservability observability;

  final List<HandObservation> _hands;

  List<HandObservation> get hands => _hands;
}
