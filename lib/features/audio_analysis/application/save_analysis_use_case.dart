import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_repository.dart';

/// Persists a completed V2 document through the domain repository contract.
final class SaveAnalysisUseCase {
  const SaveAnalysisUseCase(this._repository);

  final AnalysisRepository _repository;

  Future<AppResult<void>> call(AnalysisSaveRequest request) =>
      _repository.save(request);
}
