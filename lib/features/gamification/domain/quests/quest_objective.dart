import 'package:strumsight/features/practice/public.dart' show PracticeMode;
import 'package:strumsight/features/practice_generator/public.dart'
    show BlockId;

import '../achievements/achievement_definition.dart' show AchievementMetric;

/// A closed reference vocabulary for a quest's measurable target.
sealed class QuestObjective {
  const QuestObjective();

  Map<String, Object?> toJson();

  /// Decodes a persisted objective without guessing a safe fallback.
  factory QuestObjective.fromJson(Object? json) {
    final object = _requireObject(json, 'json');
    final type = _requireString(object, 'type');
    return switch (type) {
      'skillTag' => SkillTagQuestObjective(_requireString(object, 'skillTag')),
      'planBlock' => PlanBlockQuestObjective(
        BlockId.fromJson(object['blockId']),
      ),
      'practiceMode' => PracticeModeQuestObjective(
        _practiceModeFromCode(_requireString(object, 'mode')),
      ),
      'metric' => MetricQuestObjective(
        _achievementMetricFromCode(_requireString(object, 'metric')),
      ),
      _ => UnknownQuestObjective(type),
    };
  }
}

/// A stable skill identifier, not user-authored display text.
final class SkillTagQuestObjective extends QuestObjective {
  factory SkillTagQuestObjective(String skillTag) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(skillTag)) {
      throw ArgumentError.value(
        skillTag,
        'skillTag',
        'must be lower snake case',
      );
    }
    return SkillTagQuestObjective._(skillTag);
  }

  const SkillTagQuestObjective._(this.skillTag);

  final String skillTag;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'skillTag',
    'skillTag': skillTag,
  };
}

/// A typed reference to one published Practice Generator plan block.
final class PlanBlockQuestObjective extends QuestObjective {
  const PlanBlockQuestObjective(this.blockId);

  final BlockId blockId;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'planBlock',
    'blockId': blockId.toJson(),
  };
}

/// A typed reference to a published Practice mode.
final class PracticeModeQuestObjective extends QuestObjective {
  const PracticeModeQuestObjective(this.mode);

  final PracticeMode mode;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'practiceMode',
    'mode': mode.code,
  };
}

/// A typed reference to one canonical gamification measurement.
final class MetricQuestObjective extends QuestObjective {
  const MetricQuestObjective(this.metric);

  final AchievementMetric metric;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'metric',
    'metric': metric.code,
  };
}

/// Preserves an unrecognised persisted objective while preventing its use.
final class UnknownQuestObjective extends QuestObjective {
  const UnknownQuestObjective(this.typeCode);

  final String typeCode;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'type': typeCode};
}

Map<String, Object?> _requireObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  throw ArgumentError.value(value, field, 'must be an object');
}

String _requireString(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is String) return value;
  throw ArgumentError.value(value, field, 'must be a string');
}

PracticeMode _practiceModeFromCode(String code) {
  for (final mode in PracticeMode.values) {
    if (mode.code == code) return mode;
  }
  throw ArgumentError.value(code, 'mode', 'is not supported');
}

AchievementMetric _achievementMetricFromCode(String code) {
  for (final metric in AchievementMetric.values) {
    if (metric.code == code) return metric;
  }
  throw ArgumentError.value(code, 'metric', 'is not supported');
}
