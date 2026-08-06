import '../foundation/app_result.dart';
import '../logging/app_logger.dart';
import 'camera_failure.dart';
import 'camera_session_lease.dart';

/// Grants one exclusive camera lease per [CameraSessionCoordinator].
///
/// The check-and-take in [acquire] runs before its first asynchronous boundary.
/// Therefore overlapping callers cannot both observe a free camera: the second
/// caller receives a retryable `camera.session_busy` failure instead of taking
/// the camera from the active route.
final class CameraSessionCoordinator {
  CameraSessionCoordinator({
    this._logger = const NoopAppLogger(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppLogger _logger;
  final DateTime Function() _now;

  _Lease? _active;
  int _nextLeaseNumber = 0;

  /// The current owner, or null when the camera is free.
  CameraOwner? get activeOwner {
    final lease = _active;
    return lease != null && lease.isActive ? lease.owner : null;
  }

  /// Takes the camera for [owner].
  ///
  /// [onRevoke] must close the owning route's capture and stream before the
  /// lease is released. It is run for route leave, backgrounding, and explicit
  /// shutdown; failures are logged but never leave the camera locked forever.
  Future<AppResult<CameraSessionLease>> acquire(
    CameraOwner owner, {
    Future<void> Function()? onRevoke,
  }) async {
    final current = _active;
    if (current != null && current.isActive) {
      _log(
        event: 'camera.session.busy',
        owner: owner,
        reason: 'already_held',
        leaseId: current.leaseId,
        level: LogLevel.warning,
      );
      return Failure(
        CameraFailureMapper.map(
          CameraFailureKind.busy,
          cause: 'held by ${current.owner.name}',
        ),
      );
    }

    final lease = _Lease(
      coordinator: this,
      leaseId: 'camera-${_nextLeaseNumber++}',
      owner: owner,
      onRevoke: onRevoke,
    );
    _active = lease;
    _log(
      event: 'camera.session.acquired',
      owner: owner,
      reason: 'acquire',
      leaseId: lease.leaseId,
      level: LogLevel.debug,
    );
    return Success(lease);
  }

  /// Revokes the active lease, if any.
  ///
  /// The owner's teardown completes before the lease becomes available. This
  /// prevents a new owner from opening the camera while the former stream is
  /// still live.
  Future<void> revokeActive({
    CameraSessionRevocationReason reason =
        CameraSessionRevocationReason.explicit,
  }) async {
    final lease = _active;
    if (lease == null || !lease.isActive) return;
    await lease._revoke(reason: reason);
  }

  void _clear(_Lease lease) {
    // A stale release must never free a newer owner's session.
    if (identical(_active, lease)) _active = null;
  }

  void _log({
    required String event,
    required CameraOwner owner,
    required String reason,
    required String leaseId,
    required LogLevel level,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final fields = <String, Object?>{
      'owner': owner.name,
      'reason': reason,
      'timestamp': _now().toUtc().toIso8601String(),
      'leaseId': leaseId,
    };
    switch (level) {
      case LogLevel.debug:
        _logger.debug(event, fields: fields);
      case LogLevel.info:
        _logger.info(event, fields: fields);
      case LogLevel.warning:
        _logger.warning(
          event,
          error: error,
          stackTrace: stackTrace,
          fields: fields,
        );
      case LogLevel.error:
        _logger.error(
          event,
          error: error!,
          stackTrace: stackTrace!,
          fields: fields,
        );
    }
  }
}

final class _Lease implements CameraSessionLease {
  _Lease({
    required this.coordinator,
    required this.leaseId,
    required this.owner,
    required this.onRevoke,
  });

  final CameraSessionCoordinator coordinator;
  final Future<void> Function()? onRevoke;

  @override
  final String leaseId;

  @override
  final CameraOwner owner;

  bool _active = true;
  bool _revoking = false;

  @override
  bool get isActive => _active;

  @override
  Future<void> release() async {
    // Revocation owns the release boundary until its teardown completes. An
    // owner may call release from its own `onRevoke`; letting that clear the
    // coordinator early would allow a second capture to start beside the
    // still-closing first stream.
    if (!_active || _revoking) return;
    _finishRelease();
  }

  void _finishRelease() {
    if (!_active) return;
    _active = false;
    coordinator._clear(this);
    coordinator._log(
      event: 'camera.session.released',
      owner: owner,
      reason: 'release',
      leaseId: leaseId,
      level: LogLevel.debug,
    );
  }

  Future<void> _revoke({required CameraSessionRevocationReason reason}) async {
    if (!_active || _revoking) return;
    _revoking = true;
    coordinator._log(
      event: 'camera.session.revoked',
      owner: owner,
      reason: reason.name,
      leaseId: leaseId,
      level: LogLevel.info,
    );
    try {
      await onRevoke?.call();
    } on Object catch (error, stackTrace) {
      coordinator._log(
        event: 'camera.session.revoke_failed',
        owner: owner,
        reason: reason.name,
        leaseId: leaseId,
        level: LogLevel.error,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _finishRelease();
    }
  }
}
