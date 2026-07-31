import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart';
import 'package:strumsight/features/practice/domain/repository/practice_session_recorder.dart';

/// A controllable [PracticeSessionRecorder] for tests.
///
/// The default result is a `Success(null)`. Inject a failure to exercise
/// the controller's "recorder error -> ShowRecoverableError" branch from
/// the brief's A5 matrix.
final class FakePracticeSessionRecorder implements PracticeSessionRecorder {
  FakePracticeSessionRecorder({AppResult<void>? recordResult})
    : recordResult = recordResult ?? const Success<void>(null);

  /// Overwrite between dispatches to control the next call's outcome.
  AppResult<void> recordResult;

  /// Number of [record] calls.
  int recordCalls = 0;

  /// Every result the controller has asked to record, in arrival order.
  final List<PracticeSessionResult> recordedResults = [];

  @override
  Future<AppResult<void>> record(PracticeSessionResult result) async {
    recordCalls++;
    recordedResults.add(result);
    return recordResult;
  }
}
