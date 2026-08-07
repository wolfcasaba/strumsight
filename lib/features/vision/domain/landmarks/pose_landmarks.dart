// E05-R14 — Pose landmark domain (ADR 0178 §Döntés 1, ADR 0186 §Döntés 1).
//
// SZŰKÍTETT felsőtest-topológia: váll, könyök, csukló, csípő és LEGFELJEBB
// egy semleges nyak-referenciapont. Szem/orr/száj/fül ID NEM létezik ebben az
// enumban — ha a provider ilyet ad, a `mapRawPoseLandmarks` mapping eldobja,
// MIELŐTT a domain típus létrejönne (nem a fogyasztó dolga szűrni).
//
// Zero-pose kimenet `notObservable`, NEM failure és NEM nullákkal töltött
// álkimenet (a hand-oldali `HandLandmarkObservability` mintája).

library;

/// The 9 stable, provider-independent upper-body landmark IDs.
///
/// `left`/`right` denote the person's PHYSICAL (anatomical) side, following
/// the `Handedness` convention and the non-mirrored input guarantee — never a
/// camera-relative side. There is deliberately no eye/nose/mouth/ear ID
/// (ADR 0186 §Döntés 1).
enum PoseLandmarkId {
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,

  /// The at most one neutral head/neck reference point, used only as a neck
  /// posture proxy. Absent (never zero-filled) when the provider cannot
  /// localize it.
  neckReference,
}

/// The canonical wire names the mapping accepts for each retained ID.
///
/// A raw provider key that is not in this map is DROPPED by
/// [mapRawPoseLandmarks] — this is the single machine-checked allow-list the
/// privacy audit pins.
const Map<String, PoseLandmarkId> poseLandmarkIdByRawName =
    <String, PoseLandmarkId>{
      'left_shoulder': PoseLandmarkId.leftShoulder,
      'right_shoulder': PoseLandmarkId.rightShoulder,
      'left_elbow': PoseLandmarkId.leftElbow,
      'right_elbow': PoseLandmarkId.rightElbow,
      'left_wrist': PoseLandmarkId.leftWrist,
      'right_wrist': PoseLandmarkId.rightWrist,
      'left_hip': PoseLandmarkId.leftHip,
      'right_hip': PoseLandmarkId.rightHip,
      'neck': PoseLandmarkId.neckReference,
    };

/// One pose landmark in the model's non-mirrored, resolution-independent
/// normalized frame space.
///
/// `x`/`y` are normalized to `[0, 1]`; `z` is a provider-relative depth;
/// `visibility` ∈ `[0, 1]` is the provider's self-reported confidence that
/// the point is actually visible.
final class PoseLandmarkPoint {
  PoseLandmarkPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  }) {
    if (!(x.isFinite && y.isFinite && z.isFinite)) {
      throw ArgumentError('PoseLandmarkPoint coordinates must be finite');
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
      other is PoseLandmarkPoint &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.visibility == visibility;

  @override
  int get hashCode => Object.hash(x, y, z, visibility);
}

/// Whether the provider observed an upper body at all.
///
/// `notObservable` is the explicit "we cannot tell" signal — NOT a failure.
enum PoseObservability { notObservable, observed }

/// The complete, privacy-minimized output of one `PoseLandmarkProvider.infer`
/// call.
///
/// The `landmarks` map carries exactly the IDs the provider localized —
/// missing IDs are absent, never zero-filled.
final class PoseLandmarks {
  PoseLandmarks({
    required this.timestampUs,
    required this.observability,
    required Map<PoseLandmarkId, PoseLandmarkPoint> landmarks,
  }) : _landmarks = Map<PoseLandmarkId, PoseLandmarkPoint>.unmodifiable(
         landmarks,
       ) {
    if (timestampUs < 0) {
      throw ArgumentError.value(
        timestampUs,
        'timestampUs',
        'Must be non-negative.',
      );
    }
  }

  /// No observable upper body — no landmarks, explicitly not a failure.
  factory PoseLandmarks.notObservable({required int timestampUs}) =>
      PoseLandmarks(
        timestampUs: timestampUs,
        observability: PoseObservability.notObservable,
        landmarks: const <PoseLandmarkId, PoseLandmarkPoint>{},
      );

  final int timestampUs;
  final PoseObservability observability;

  final Map<PoseLandmarkId, PoseLandmarkPoint> _landmarks;

  /// The SOLE accessor — callers never use provider indices.
  PoseLandmarkPoint? byId(PoseLandmarkId id) => _landmarks[id];

  /// Number of retained landmarks.
  int get count => _landmarks.length;

  /// The retained IDs, in the stable enum order.
  List<PoseLandmarkId> get presentIds => PoseLandmarkId.values
      .where(_landmarks.containsKey)
      .toList(growable: false);

  /// The privacy-audit surface: every field that may leave this object via
  /// serialization, logging or diagnostics.
  ///
  /// The key set is pinned by `pose_privacy_audit_test.dart`; a new field can
  /// only enter by updating that snapshot.
  Map<String, Object?> toAuditMap() => <String, Object?>{
    'timestamp_us': timestampUs,
    'observability': observability.name,
    'landmarks': <String, Object?>{
      for (final id in presentIds)
        id.name: <String, Object?>{
          'x': _landmarks[id]!.x,
          'y': _landmarks[id]!.y,
          'z': _landmarks[id]!.z,
          'visibility': _landmarks[id]!.visibility,
        },
    },
  };

  /// Log-safe representation: counts only, no coordinates.
  @override
  String toString() =>
      'PoseLandmarks(timestampUs: $timestampUs, '
      'observability: ${observability.name}, count: $count)';
}

/// Raw, provider-side landmark payload before mapping.
///
/// `name` is the provider's own key (e.g. `left_shoulder`, but also
/// `nose`/`left_eye` for providers that emit face points).
final class RawPoseLandmark {
  const RawPoseLandmark({
    required this.name,
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  final String name;
  final double x;
  final double y;
  final double z;
  final double visibility;
}

/// Maps a raw provider payload onto the retained 9-point topology.
///
/// Every raw name outside [poseLandmarkIdByRawName] — face points included —
/// is DROPPED here, so no face landmark can ever reach a domain object,
/// persistence, insight or log (ADR 0178 §Döntés 1, ADR 0186 §Döntés 1).
/// Non-finite coordinates and out-of-range visibility are dropped too, rather
/// than clamped into a plausible-looking fake.
PoseLandmarks mapRawPoseLandmarks({
  required int timestampUs,
  required List<RawPoseLandmark> raw,
}) {
  final landmarks = <PoseLandmarkId, PoseLandmarkPoint>{};
  for (final candidate in raw) {
    final id = poseLandmarkIdByRawName[candidate.name];
    if (id == null) continue;
    if (!(candidate.x.isFinite &&
        candidate.y.isFinite &&
        candidate.z.isFinite)) {
      continue;
    }
    if (!(candidate.visibility >= 0 && candidate.visibility <= 1)) continue;
    landmarks[id] = PoseLandmarkPoint(
      x: candidate.x,
      y: candidate.y,
      z: candidate.z,
      visibility: candidate.visibility,
    );
  }
  if (landmarks.isEmpty) {
    return PoseLandmarks.notObservable(timestampUs: timestampUs);
  }
  return PoseLandmarks(
    timestampUs: timestampUs,
    observability: PoseObservability.observed,
    landmarks: landmarks,
  );
}
