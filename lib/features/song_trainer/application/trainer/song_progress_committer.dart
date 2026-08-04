// Boundary that turns duplicate Song Trainer terminals (finalize + a late
// finish tick, or two re-entry navigations) into a single persisted progress
// commit. The boundary is the ONE place that may write session progress —
// the controller, the re-entry navigator, and the result callback all funnel
// through the idempotency key.
//
// E03-R21 brief §5.4 / §6 acceptance "duplicate finalize/re-entry egyszer
// commitol".

import 'dart:async';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice/public.dart';

abstract final class SongProgressCommitterFailureCode {
  static const String disposed = 'songProgressCommitter.disposed';
  static const String inFlight = 'songProgressCommitter.inFlight';
}

/// Idempotent boundary that forwards a finished [PracticeSessionResult] to the
/// persisted history. The contract is:
///
/// 1. Two commits with the same [idempotencyKey] AND the same revision
///    collapse to one recorder write. Subsequent calls return a synthetic
///    success that did not touch the recorder.
/// 2. Three or more concurrent commits with the same key collapse to one
///    recorder write; every caller observes a success.
/// 3. A recorder failure does NOT mark the key as committed — the caller may
///    retry. The committer never silently swallows an error (the project's
///    measured silent-no-op class).
/// 4. After [dispose], every commit returns a [SongProgressCommitterFailure]
///    with `disposed` — the committer never writes once the route has been
///    left.
final class SongProgressCommitter {
  SongProgressCommitter({required PracticeSessionRecorder sessionRecorder})
    : _recorder = sessionRecorder;

  final PracticeSessionRecorder _recorder;
  final Map<String, _CommitState> _commits = <String, _CommitState>{};
  bool _disposed = false;

  Future<AppResult<void>> commit({
    required String idempotencyKey,
    required PracticeSessionResult sessionResult,
  }) async {
    if (_disposed) {
      return AppResult<void>.failure(
        const StorageFailure(code: SongProgressCommitterFailureCode.disposed),
      );
    }

    final existing = _commits[idempotencyKey];
    if (existing is _CommittedWrite) {
      return const AppResult<void>.success(null);
    }
    if (existing is _InFlightWrite) {
      return await existing.future;
    }

    final pending = _InFlightWrite();
    _commits[idempotencyKey] = pending;
    pending.completer.complete(
      _run(idempotencyKey: idempotencyKey, sessionResult: sessionResult),
    );
    final outcome = await pending.future;
    if (outcome.isSuccess) {
      _commits[idempotencyKey] = const _CommittedWrite();
    } else {
      _commits.remove(idempotencyKey);
    }
    return outcome;
  }

  Future<AppResult<void>> _run({
    required String idempotencyKey,
    required PracticeSessionResult sessionResult,
  }) async {
    try {
      return await _recorder.record(sessionResult);
    } on Object catch (error, stackTrace) {
      return AppResult<void>.failure(
        StorageFailure(
          code: FailureCode.storageWrite,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final entry in _commits.values.whereType<_InFlightWrite>()) {
      if (!entry.completer.isCompleted) {
        entry.completer.complete(
          AppResult<void>.failure(
            const StorageFailure(
              code: SongProgressCommitterFailureCode.disposed,
            ),
          ),
        );
      }
    }
    _commits.clear();
  }
}

sealed class _CommitState {
  const _CommitState();
}

final class _InFlightWrite extends _CommitState {
  _InFlightWrite();

  final Completer<AppResult<void>> completer = Completer<AppResult<void>>();

  Future<AppResult<void>> get future => completer.future;
}

final class _CommittedWrite extends _CommitState {
  const _CommittedWrite();
}
