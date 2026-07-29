import '../../foundation/app_failure.dart';
import '../../foundation/app_result.dart';
import '../../logging/app_logger.dart';
import 'audio_session_lease.dart';

/// Grants exclusive microphone ownership (SDD Ch2, Kör 9 §9.2).
///
/// One owner at a time. A second owner gets a controlled busy failure — it
/// does NOT silently steal the microphone from the running one (ADR 0056):
/// stealing would leave the first owner's UI claiming it is listening while
/// its stream is dead, which is the silent no-op class this app refuses.
///
/// The critical section (is anyone holding it? → take it) runs synchronously
/// before the first `await`, so two overlapping `acquire` calls cannot both
/// see a free session.
final class AudioSessionCoordinator {
  AudioSessionCoordinator({this._logger = const NoopAppLogger()});

  final AppLogger _logger;

  _Lease? _active;

  /// Who holds the microphone right now, or null when it is free.
  AudioOwner? get activeOwner {
    final lease = _active;
    return lease != null && lease.isActive ? lease.owner : null;
  }

  /// Takes the microphone for [owner].
  ///
  /// [onRevoke] is how the coordinator stops that owner when the app leaves
  /// the foreground: it must tear down the owner's capture (subscription,
  /// isolate) — the lease is released for it afterwards.
  Future<AppResult<AudioSessionLease>> acquire(
    AudioOwner owner, {
    Future<void> Function()? onRevoke,
  }) async {
    final current = _active;
    if (current != null && current.isActive) {
      _logger.warning(
        'audio.session.busy',
        fields: {'requested': owner.name, 'holder': current.owner.name},
      );
      return Failure(
        AudioFailure(
          code: FailureCode.audioSessionBusy,
          cause: 'held by ${current.owner.name}',
        ),
      );
    }
    final lease = _Lease(this, owner, onRevoke);
    _active = lease;
    _logger.debug('audio.session.acquired', fields: {'owner': owner.name});
    return Success(lease);
  }

  /// Stops whoever holds the microphone (app backgrounded, §9.4).
  ///
  /// Safe to call when the session is free. The owner's `onRevoke` runs first
  /// so the stream and the DSP isolate are gone before the lease is freed.
  Future<void> revokeActive() async {
    final lease = _active;
    if (lease == null || !lease.isActive) return;
    await lease._revoke();
  }

  void _clear(_Lease lease) {
    // Only clear if this lease is still the holder: a release arriving after
    // the next owner acquired must not free the NEW session (round 114 class).
    if (identical(_active, lease)) _active = null;
  }
}

final class _Lease implements AudioSessionLease {
  _Lease(this._coordinator, this.owner, this._onRevoke);

  final AudioSessionCoordinator _coordinator;
  final Future<void> Function()? _onRevoke;

  @override
  final AudioOwner owner;

  bool _active = true;
  bool _revoking = false;

  @override
  bool get isActive => _active;

  @override
  Future<void> release() async {
    if (!_active) return;
    _active = false;
    _coordinator._clear(this);
    _coordinator._logger.debug(
      'audio.session.released',
      fields: {'owner': owner.name},
    );
  }

  Future<void> _revoke() async {
    if (!_active || _revoking) return;
    _revoking = true;
    _coordinator._logger.info(
      'audio.session.revoked',
      fields: {'owner': owner.name},
    );
    try {
      // The owner's teardown normally releases this lease itself; the release
      // below then no-ops. If the teardown throws we still free the session —
      // a crashed owner must not keep the microphone locked forever.
      await _onRevoke?.call();
    } catch (error, stackTrace) {
      _coordinator._logger.error(
        'audio.session.revoke_failed',
        error: error,
        stackTrace: stackTrace,
        fields: {'owner': owner.name},
      );
    } finally {
      await release();
    }
  }
}
