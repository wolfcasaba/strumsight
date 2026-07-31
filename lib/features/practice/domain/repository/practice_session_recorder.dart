import '../../../../core/foundation/app_result.dart';
import '../model/practice_session_result.dart';

/// Persists the immutable [PracticeSessionResult] of one finished practice
/// session (ADR 0077 §12).
///
/// The controller depends on this interface only — the production provider
/// wires up a [NoopPracticeSessionRecorder] until the Kör 18 history
/// repository lands. The no-op returns `Success` without writing
/// anywhere; it does NOT swallow errors via `try/catch` (the project's
/// measured silent-no-op class).
abstract interface class PracticeSessionRecorder {
  /// Persist [result]. Implementations are expected to be idempotent on
  /// best-effort — the controller enforces single-flight and passes the
  /// same result object on every FinishPractice attempt.
  Future<AppResult<void>> record(PracticeSessionResult result);
}

/// The production-default [PracticeSessionRecorder] — does nothing.
///
/// Returns `Success(null)` so the controller's finish path is exercised
/// end-to-end on real devices. Will be replaced by a real repository in
/// Kör 18.
final class NoopPracticeSessionRecorder implements PracticeSessionRecorder {
  const NoopPracticeSessionRecorder();

  @override
  Future<AppResult<void>> record(PracticeSessionResult result) async {
    return const Success<void>(null);
  }
}
