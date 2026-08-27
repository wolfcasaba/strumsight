import '../../../core/foundation/app_result.dart';
import '../../audio_analysis/application/delete_analysis_use_case.dart';
import '../../audio_analysis/domain/analysis_repository.dart';
import '../domain/library_delete_actions.dart';
import '../domain/library_delete_scope.dart';

/// Real [LibraryDeleteActions] for [LibraryItemType.analysis] items.
///
/// Every scope resolves to the existing [AnalysisRepository] / [AnalysisAudioPort]
/// pair (§0.0/B3) — the same ports [DeleteAnalysisUseCase] already composes:
/// - [LibraryDeleteScope.rawOnly] deletes only the retained capture, leaving
///   the document/index (and therefore the result) untouched.
/// - [LibraryDeleteScope.resultOnly] deletes only the document/index,
///   leaving any retained capture untouched.
/// - [LibraryDeleteScope.everything] deletes both, mirroring
///   [DeleteAnalysisUseCase] exactly.
final class AnalysisLibraryDeleteActions implements LibraryDeleteActions {
  const AnalysisLibraryDeleteActions({
    required AnalysisRepository repository,
    AnalysisAudioPort audio = const NoAudioPort(),
  }) : _repository = repository,
       _audio = audio;

  final AnalysisRepository _repository;
  final AnalysisAudioPort _audio;

  @override
  Future<AppResult<void>> delete(String id, LibraryDeleteScope scope) async {
    switch (scope) {
      case LibraryDeleteScope.rawOnly:
        await _audio.deleteIfExists(id);
        return const AppResult<void>.success(null);
      case LibraryDeleteScope.resultOnly:
        return _repository.delete(id);
      case LibraryDeleteScope.everything:
        final result = await _repository.delete(id);
        if (result.isFailure) return result;
        await _audio.deleteIfExists(id);
        return result;
    }
  }
}
