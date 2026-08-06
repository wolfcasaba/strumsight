/// Everything that may exclusively own the optional camera.
///
/// The owner is recorded in controlled busy failures and lifecycle events, so
/// a future UI can explain which flow still owns the camera without exposing
/// image, device, or personal data.
enum CameraOwner { visionSetup, visionPractice, songVision, labCapture }

/// Safe, finite causes for ending a camera session.
///
/// This enum deliberately prevents a caller from passing arbitrary (and
/// potentially sensitive) text into the structured lifecycle log.
enum CameraSessionRevocationReason { appBackground, routeLeave, explicit }

/// The exclusive right to use the camera.
///
/// A lease is single-use. Once released or revoked, it stays inactive and a
/// later acquisition receives a new lease. That prevents a stale route from
/// freeing or reopening another route's camera session.
abstract interface class CameraSessionLease {
  /// Stable only for the lifetime of this process; intended for lifecycle logs.
  String get leaseId;

  CameraOwner get owner;

  /// False after release or lifecycle revocation.
  bool get isActive;

  /// Returns the camera lease. Safe to call more than once.
  Future<void> release();
}
