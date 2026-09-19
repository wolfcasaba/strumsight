/// Persistence of a finished Vision session (E09-R28a).
///
/// `visionSessionResultListenerProvider` used to default to `(_) {}` — the
/// aggregate a session produced was built, handed over, and dropped, so
/// `VisionSessionRepository` never saw a single entry and everything
/// downstream of it (the privacy centre's session list, the practice
/// generator's Vision evidence adapter) had nothing to read. This recorder is
/// that default.
library;

import '../../../core/logging/app_logger.dart';
import '../data/persistence/vision_session_repository.dart';
import '../domain/vision_session_result.dart';

/// Writes finished sessions to local history, reporting write failures.
///
/// The write is fire-and-forget because the caller is a synchronous
/// finalization step, but a failure is logged rather than swallowed: a
/// storage write hidden inside a bare `try`/`catch` is a silent no-op, and a
/// silent no-op here looks exactly like a working session that saved nothing.
final class VisionSessionResultRecorder {
  VisionSessionResultRecorder({
    required this.repository,
    required this.modelVersions,
    required this.logger,
  });

  final VisionSessionRepository repository;

  /// Model provenance stored with the entry. The codec rejects an empty map,
  /// so a session recorded while the models are `deferred` says so.
  final Map<String, String> modelVersions;

  final AppLogger logger;

  /// The pending write, exposed so a test can await the round trip instead of
  /// polling the store.
  Future<void> get pending => _pending;
  Future<void> _pending = Future<void>.value();

  void call(VisionSessionResult result) {
    _pending = _pending.then((_) => _save(result));
  }

  Future<void> _save(VisionSessionResult result) async {
    try {
      await repository.save(result, modelVersions: modelVersions);
    } on Object catch (error, stackTrace) {
      logger.error(
        'vision.session.persist_failed',
        error: error,
        stackTrace: stackTrace,
        fields: <String, Object?>{'sessionId': result.session.id.value},
      );
    }
  }
}
