import 'dart:async';

import '../../../../core/foundation/app_result.dart';
import '../domain/model/practice_history_entry.dart';
import '../domain/model/practice_session_result.dart' as presult;
import '../domain/repository/practice_history_repository.dart';
import '../domain/repository/practice_session_recorder.dart';
import 'practice_session_result_history_mapper.dart';

/// The production [PracticeSessionRecorder] — converts each finished
/// [presult.PracticeSessionResult] into a [PracticeHistoryEntry] and writes
/// it through the [PracticeHistoryRepository] (ADR 0084 §Döntés 4).
///
/// Failures **never** become silent no-ops: the repository's [AppResult]
/// carries the failure through, and the controller (already wired for
/// [ShowRecoverableError]) surfaces it to the user.
///
/// Honors `FeatureFlags.practiceDetailedHistoryEnabled`: when the flag is
/// off, only the session-summary is persisted (no per-attempt detail).
class PracticeHistoryRecorder implements PracticeSessionRecorder {
  const PracticeHistoryRecorder({
    required this._repository,
    required this._mapperFactory,
  });

  final PracticeHistoryRepository _repository;
  final PracticeSessionResultHistoryMapper Function() _mapperFactory;

  @override
  Future<AppResult<void>> record(presult.PracticeSessionResult result) async {
    final mapper = _mapperFactory();
    final entry = mapper.toHistoryEntry(result);
    return _repository.save(entry);
  }
}
