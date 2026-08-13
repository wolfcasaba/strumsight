import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_repository.dart';

/// Invalidates whatever cache entry a future round keys by analysis id.
///
/// No production implementation exists yet — the E06-R28 cache round wires
/// a real port here without touching this use case's contract (ADR 0247
/// §Döntés 4). Tests exercise this through a fake.
abstract interface class AnalysisCachePort {
  Future<void> invalidate(String documentId);
}

/// Deletes the optional retained audio file for an analysis id, if any.
///
/// The R21 [AnalysisRepository] never persists audio bytes today
/// ([AudioRetentionPolicy.defaultPolicy]), so a production implementation
/// of this port is also a follow-up; the cell exists so the deletion
/// contract is already complete when audio retention lands.
abstract interface class AnalysisAudioPort {
  Future<void> deleteIfExists(String documentId);
}

/// A no-op audio port — the safe default while no round retains audio.
final class NoAudioPort implements AnalysisAudioPort {
  const NoAudioPort();

  @override
  Future<void> deleteIfExists(String documentId) async {}
}

/// A no-op cache port — the safe default while no round has a cache.
final class NoCachePort implements AnalysisCachePort {
  const NoCachePort();

  @override
  Future<void> invalidate(String documentId) async {}
}

/// Deletes an analysis completely: document + index (via the unchanged R21
/// [AnalysisRepository] contract), plus cache and optional audio residue
/// through explicit ports (ADR 0247 §Döntés 4). "The index updates, the
/// file stays" is never an acceptable outcome — every owner must confirm.
final class DeleteAnalysisUseCase {
  const DeleteAnalysisUseCase({
    required AnalysisRepository repository,
    AnalysisCachePort cache = const NoCachePort(),
    AnalysisAudioPort audio = const NoAudioPort(),
  }) : _repository = repository,
       _cache = cache,
       _audio = audio;

  final AnalysisRepository _repository;
  final AnalysisCachePort _cache;
  final AnalysisAudioPort _audio;

  Future<AppResult<void>> call(String documentId) async {
    final result = await _repository.delete(documentId);
    if (result.isFailure) return result;
    await _cache.invalidate(documentId);
    await _audio.deleteIfExists(documentId);
    return result;
  }
}
