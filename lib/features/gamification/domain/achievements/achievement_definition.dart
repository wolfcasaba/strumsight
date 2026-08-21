/// The six canonical learning-event kinds measured by the gamification input.
enum AchievementEventKind {
  practice('practice'),
  song('song'),
  analysis('analysis'),
  plan('plan'),
  tutor('tutor'),
  vision('vision');

  const AchievementEventKind(this.code);

  final String code;
}

/// Numeric evidence available to achievement objectives.
enum AchievementMetric {
  eventCount('eventCount'),
  durationSeconds('durationSeconds'),
  score('score'),
  baseXp('baseXp'),
  durationXp('durationXp'),
  qualityXp('qualityXp'),
  improvementXp('improvementXp'),
  diversityXp('diversityXp'),
  totalXp('totalXp');

  const AchievementMetric(this.code);

  final String code;
}

/// The only measured distinctness dimension available to this catalog version.
enum AchievementDistinctDimension {
  activitySource('activitySource');

  const AchievementDistinctDimension(this.code);

  final String code;
}

/// Product grouping for a curated achievement.
enum AchievementCategory {
  consistency,
  practice,
  songs,
  rhythm,
  chords,
  technique,
  analysis,
  exploration,
  personalBest,
  accessibilityNeutral,
}

/// A closed, typed condition that a future evaluator can index.
sealed class AchievementObjective {
  const AchievementObjective();
}

/// Reaches a number of events of one measured kind.
final class CountAchievementObjective extends AchievementObjective {
  const CountAchievementObjective({
    required this.eventKind,
    required this.target,
  }) : assert(target > 0);

  final AchievementEventKind eventKind;
  final int target;
}

/// Reaches a numeric evidence threshold for one measured event kind.
final class ThresholdAchievementObjective extends AchievementObjective {
  const ThresholdAchievementObjective({
    required this.eventKind,
    required this.metric,
    required this.minimum,
  }) : assert(minimum >= 0);

  final AchievementEventKind eventKind;
  final AchievementMetric metric;
  final num minimum;
}

/// Reaches a number of distinct activity sources for one measured event kind.
final class DistinctAchievementObjective extends AchievementObjective {
  const DistinctAchievementObjective({
    required this.eventKind,
    required this.dimension,
    required this.target,
  }) : assert(target > 0);

  final AchievementEventKind eventKind;
  final AchievementDistinctDimension dimension;
  final int target;
}

/// Requires measured event kinds in an explicit order.
final class SequenceAchievementObjective extends AchievementObjective {
  SequenceAchievementObjective({required List<AchievementEventKind> eventKinds})
    : eventKinds = List<AchievementEventKind>.unmodifiable(eventKinds) {
    if (eventKinds.isEmpty) {
      throw ArgumentError.value(eventKinds, 'eventKinds', 'must not be empty');
    }
  }

  final List<AchievementEventKind> eventKinds;
}

/// Requires all contained typed objectives.
final class CompoundAchievementObjective extends AchievementObjective {
  CompoundAchievementObjective({required List<AchievementObjective> objectives})
    : objectives = List<AchievementObjective>.unmodifiable(objectives) {
    if (objectives.isEmpty) {
      throw ArgumentError.value(objectives, 'objectives', 'must not be empty');
    }
  }

  final List<AchievementObjective> objectives;
}

/// Preserves an unrecognised persisted objective type while preventing its use.
final class UnknownAchievementObjective extends AchievementObjective {
  const UnknownAchievementObjective(this.typeCode);

  final String typeCode;
}

/// Immutable, localized achievement content with a stable persisted identifier.
final class AchievementDefinition {
  factory AchievementDefinition({
    required String id,
    required AchievementCategory category,
    required String titleKey,
    required String descriptionKey,
    required String accessibilityDescriptionKey,
    required List<AchievementObjective> objectives,
    required List<String> tierPrerequisiteIds,
    required bool hidden,
    required int version,
    required bool deprecated,
    int? deprecatedSinceVersion,
  }) {
    _requireStableId(id, 'id');
    _requireLocalizationKey(titleKey, 'titleKey');
    _requireLocalizationKey(descriptionKey, 'descriptionKey');
    _requireLocalizationKey(
      accessibilityDescriptionKey,
      'accessibilityDescriptionKey',
    );
    if (objectives.isEmpty) {
      throw ArgumentError.value(objectives, 'objectives', 'must not be empty');
    }
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'must be positive');
    }
    if (deprecatedSinceVersion != null && !deprecated) {
      throw ArgumentError.value(
        deprecatedSinceVersion,
        'deprecatedSinceVersion',
        'requires deprecated to be true',
      );
    }
    if (deprecatedSinceVersion != null && deprecatedSinceVersion < version) {
      throw ArgumentError.value(
        deprecatedSinceVersion,
        'deprecatedSinceVersion',
        'must not predate the definition version',
      );
    }
    for (final prerequisiteId in tierPrerequisiteIds) {
      _requireStableId(prerequisiteId, 'tierPrerequisiteIds');
    }
    return AchievementDefinition._(
      id: id,
      category: category,
      titleKey: titleKey,
      descriptionKey: descriptionKey,
      accessibilityDescriptionKey: accessibilityDescriptionKey,
      objectives: List<AchievementObjective>.unmodifiable(objectives),
      tierPrerequisiteIds: List<String>.unmodifiable(tierPrerequisiteIds),
      hidden: hidden,
      version: version,
      deprecated: deprecated,
      deprecatedSinceVersion: deprecatedSinceVersion,
    );
  }

  const AchievementDefinition._({
    required this.id,
    required this.category,
    required this.titleKey,
    required this.descriptionKey,
    required this.accessibilityDescriptionKey,
    required this.objectives,
    required this.tierPrerequisiteIds,
    required this.hidden,
    required this.version,
    required this.deprecated,
    required this.deprecatedSinceVersion,
  });

  final String id;
  final AchievementCategory category;
  final String titleKey;
  final String descriptionKey;
  final String accessibilityDescriptionKey;
  final List<AchievementObjective> objectives;
  final List<String> tierPrerequisiteIds;
  final bool hidden;
  final int version;
  final bool deprecated;
  final int? deprecatedSinceVersion;
}

void _requireStableId(String value, String name) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be lower snake case');
  }
}

void _requireLocalizationKey(String value, String name) {
  if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a lowerCamelCase key');
  }
}
