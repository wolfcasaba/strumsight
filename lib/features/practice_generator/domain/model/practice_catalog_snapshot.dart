/// Revisioned, deterministic exercise-candidate snapshot for one generation.
library;

import 'exercise_candidate.dart';

/// The revision dimension that differs from another catalog snapshot.
enum CatalogRevisionMismatch { catalog, content }

/// One explicit exclusion made while adapting catalog content.
final class CandidateExclusionWarning {
  const CandidateExclusionWarning({
    required this.reason,
    required this.source,
    required this.exerciseId,
    required this.detail,
  });

  final CandidateExclusionReason reason;
  final String source;
  final String exerciseId;
  final String detail;

  String get sortKey => '${reason.code}:$source:$exerciseId:$detail';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CandidateExclusionWarning &&
          other.reason == reason &&
          other.source == source &&
          other.exerciseId == exerciseId &&
          other.detail == detail;

  @override
  int get hashCode => Object.hash(reason, source, exerciseId, detail);
}

/// Stable diagnostic reasons from SDD Ch8 §14.6.
enum CandidateExclusionReason {
  missingPrerequisite('missingPrerequisite'),
  hardAvoid('hardAvoid'),
  unsupportedDevice('unsupportedDevice'),
  wrongTuning('wrongTuning'),
  missingAsset('missingAsset'),
  offlineUnavailable('offlineUnavailable'),
  contentLocked('contentLocked'),
  safetyConflict('safetyConflict'),
  durationIncompatible('durationIncompatible'),
  localeUnavailable('localeUnavailable'),
  revisionMissing('revisionMissing');

  const CandidateExclusionReason(this.code);

  final String code;
}

/// Immutable catalog state and the revisions required for plan provenance.
final class PracticeCatalogSnapshot {
  PracticeCatalogSnapshot({
    required String catalogRevision,
    required String contentRevision,
    required Iterable<ExerciseCandidate> candidates,
    Iterable<CandidateExclusionWarning> warnings =
        const <CandidateExclusionWarning>[],
  }) : catalogRevision = _requiredRevision(catalogRevision, 'catalogRevision'),
       contentRevision = _requiredRevision(contentRevision, 'contentRevision'),
       candidates = _sortCandidates(candidates),
       warnings = _sortWarnings(warnings) {
    final references = <String>{};
    for (final candidate in this.candidates) {
      final reference = '${candidate.source.code}:${candidate.exerciseId}';
      if (!references.add(reference)) {
        throw ArgumentError.value(
          candidates,
          'candidates',
          'contains duplicate executable reference $reference',
        );
      }
    }
  }

  final String catalogRevision;
  final String contentRevision;
  final List<ExerciseCandidate> candidates;
  final List<CandidateExclusionWarning> warnings;

  /// Distinguishes a changed catalog membership from changed item content.
  Set<CatalogRevisionMismatch> mismatchesAgainst(
    PracticeCatalogSnapshot other,
  ) {
    final mismatches = <CatalogRevisionMismatch>{};
    if (catalogRevision != other.catalogRevision) {
      mismatches.add(CatalogRevisionMismatch.catalog);
    }
    if (contentRevision != other.contentRevision) {
      mismatches.add(CatalogRevisionMismatch.content);
    }
    return Set<CatalogRevisionMismatch>.unmodifiable(mismatches);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeCatalogSnapshot &&
          other.catalogRevision == catalogRevision &&
          other.contentRevision == contentRevision &&
          _sameList(other.candidates, candidates) &&
          _sameList(other.warnings, warnings);

  @override
  int get hashCode => Object.hash(
    catalogRevision,
    contentRevision,
    Object.hashAll(candidates),
    Object.hashAll(warnings),
  );
}

List<ExerciseCandidate> _sortCandidates(Iterable<ExerciseCandidate> input) {
  final candidates = input.toList()
    ..sort((left, right) => left.sortKey.compareTo(right.sortKey));
  return List<ExerciseCandidate>.unmodifiable(candidates);
}

List<CandidateExclusionWarning> _sortWarnings(
  Iterable<CandidateExclusionWarning> input,
) {
  final warnings = input.toList()
    ..sort((left, right) => left.sortKey.compareTo(right.sortKey));
  return List<CandidateExclusionWarning>.unmodifiable(warnings);
}

String _requiredRevision(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
