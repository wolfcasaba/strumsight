import '../../../../core/foundation/app_result.dart';
import '../models/tutor_memory_fact.dart';

/// Local-first, inspectable tutor memory persistence boundary.
abstract interface class TutorMemoryRepository {
  Future<AppResult<List<TutorMemoryFact>>> list();

  Future<AppResult<TutorMemoryFact>> saveCandidate(
    TutorMemoryCandidate candidate,
  );

  Future<AppResult<void>> update(TutorMemoryFact fact);

  Future<AppResult<void>> delete(String factId);

  Future<AppResult<void>> purgeExpired(DateTime now);

  Future<AppResult<String>> exportRedacted();

  /// Removes every local tutor key and its corruption quarantine.
  Future<AppResult<void>> deleteAllAiData();
}
