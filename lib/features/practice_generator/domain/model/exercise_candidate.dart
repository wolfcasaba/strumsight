/// A normalized, executable exercise candidate for deterministic planning.
library;

import 'plan_enums.dart';

/// The capabilities a planner may need to inspect before selecting an exercise.
enum ExerciseCapability {
  requiresMicrophone('requiresMicrophone'),
  requiresCamera('requiresCamera'),
  requiresBackingTrack('requiresBackingTrack'),
  requiresSongAsset('requiresSongAsset'),
  supportsTempo('supportsTempo'),
  supportsLoop('supportsLoop'),
  supportsDirectionScoring('supportsDirectionScoring'),
  supportsChordScoring('supportsChordScoring'),
  supportsPitchScoring('supportsPitchScoring'),
  supportsOffline('supportsOffline'),
  supportsLeftHandedUi('supportsLeftHandedUi'),
  supportsReducedMotion('supportsReducedMotion');

  const ExerciseCapability(this.code);

  final String code;
}

/// Whether a capability is supported by an exercise's executable source.
///
/// The absence of source evidence is represented by [unsupported], never by
/// an omitted map entry that a later planner could mistake for unknown.
enum CapabilitySupport { supported, unsupported }

/// Complete, explicit capability truth for one [ExerciseCandidate].
typedef ExerciseCapabilities = Map<ExerciseCapability, CapabilitySupport>;

/// Builds the required full capability map with every value unsupported.
ExerciseCapabilities allCapabilitiesUnsupported() => {
  for (final capability in ExerciseCapability.values)
    capability: CapabilitySupport.unsupported,
};

/// Ordered pedagogical load levels; this is not a health measurement.
enum LoadLevel { low, medium, high }

/// The complete six-dimension load profile required by SDD Ch8 §14.4.
final class ExerciseLoadProfile {
  const ExerciseLoadProfile({
    required this.cognitive,
    required this.frettingHand,
    required this.pickingHand,
    required this.repetition,
    required this.novelty,
    required this.concentration,
  });

  const ExerciseLoadProfile.all(LoadLevel level)
    : cognitive = level,
      frettingHand = level,
      pickingHand = level,
      repetition = level,
      novelty = level,
      concentration = level;

  final LoadLevel cognitive;
  final LoadLevel frettingHand;
  final LoadLevel pickingHand;
  final LoadLevel repetition;
  final LoadLevel novelty;
  final LoadLevel concentration;
}

/// The bounded duration interval one candidate can execute.
final class SupportedDurations {
  SupportedDurations({required this.minimum, required this.maximum}) {
    if (minimum.isNegative || maximum.isNegative || minimum > maximum) {
      throw ArgumentError('duration bounds must be non-negative and ordered');
    }
  }

  factory SupportedDurations.exact(Duration duration) =>
      SupportedDurations(minimum: duration, maximum: duration);

  final Duration minimum;
  final Duration maximum;
}

/// The inclusive authored difficulty range for an exercise.
final class DifficultyRange {
  DifficultyRange({required String minimum, required String maximum})
    : minimum = _requiredCode(minimum, 'minimum'),
      maximum = _requiredCode(maximum, 'maximum');

  factory DifficultyRange.exact(String code) =>
      DifficultyRange(minimum: code, maximum: code);

  final String minimum;
  final String maximum;
}

/// A practice item that refers only to content an existing executor can run.
final class ExerciseCandidate {
  ExerciseCandidate({
    required String exerciseId,
    required this.source,
    required Iterable<String> skillTargets,
    required Iterable<String> prerequisites,
    required this.supportedDurations,
    required this.difficultyRange,
    required Map<ExerciseCapability, CapabilitySupport> capabilities,
    required this.loadProfile,
    required this.offlineAvailable,
    required String contentRevision,
  }) : exerciseId = _requiredCode(exerciseId, 'exerciseId'),
       skillTargets = _requiredCodes(skillTargets, 'skillTargets'),
       prerequisites = _requiredCodes(prerequisites, 'prerequisites'),
       capabilities = _completeCapabilities(capabilities),
       contentRevision = _requiredCode(contentRevision, 'contentRevision');

  final String exerciseId;
  final CandidateSource source;
  final List<String> skillTargets;
  final List<String> prerequisites;
  final SupportedDurations supportedDurations;
  final DifficultyRange difficultyRange;
  final ExerciseCapabilities capabilities;
  final ExerciseLoadProfile loadProfile;
  final bool offlineAvailable;
  final String contentRevision;

  /// Stable lexical key used by [PracticeCatalogSnapshot] ordering.
  String get sortKey => '${source.code}:$exerciseId:$contentRevision';
}

ExerciseCapabilities _completeCapabilities(
  Map<ExerciseCapability, CapabilitySupport> capabilities,
) {
  final missing = ExerciseCapability.values
      .where((capability) => !capabilities.containsKey(capability))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    throw ArgumentError.value(
      capabilities,
      'capabilities',
      'must explicitly include every ExerciseCapability',
    );
  }
  return Map<ExerciseCapability, CapabilitySupport>.unmodifiable(capabilities);
}

List<String> _requiredCodes(Iterable<String> values, String name) {
  final result = values.map((value) => _requiredCode(value, name)).toList();
  if (result.isEmpty) {
    throw ArgumentError.value(values, name, 'must not be empty');
  }
  return List<String>.unmodifiable(result);
}

String _requiredCode(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}
