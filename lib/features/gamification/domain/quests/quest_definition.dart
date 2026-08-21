import 'quest_objective.dart';
import 'quest_schedule.dart';

/// Current schema for persisted [QuestDefinition] records.
const int questDefinitionSchemaVersion = 1;

/// The recurrence period selected by the quest generator.
enum QuestCadence { daily, weekly }

/// The fixed XP receipt parameters granted when a quest completes.
final class QuestReward {
  factory QuestReward({
    required int baseXp,
    required int bonusXp,
    required int policyVersion,
  }) {
    if (baseXp < 0 ||
        bonusXp < 0 ||
        policyVersion < 1 ||
        baseXp + bonusXp < 1) {
      throw ArgumentError(
        'a quest reward must grant positive XP with a positive policy version',
      );
    }
    return QuestReward._(
      baseXp: baseXp,
      bonusXp: bonusXp,
      policyVersion: policyVersion,
    );
  }

  const QuestReward._({
    required this.baseXp,
    required this.bonusXp,
    required this.policyVersion,
  });

  final int baseXp;
  final int bonusXp;
  final int policyVersion;

  int get totalXp => baseXp + bonusXp;

  Map<String, Object?> toJson() => <String, Object?>{
    'baseXp': baseXp,
    'bonusXp': bonusXp,
    'policyVersion': policyVersion,
  };

  factory QuestReward.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be an object');
    }
    final baseXp = _requireInt(json, 'baseXp');
    final bonusXp = _requireInt(json, 'bonusXp');
    final policyVersion = _requireInt(json, 'policyVersion');
    if (baseXp < 0 ||
        bonusXp < 0 ||
        policyVersion < 1 ||
        baseXp + bonusXp < 1) {
      throw ArgumentError.value(
        json,
        'json',
        'must describe a positive reward',
      );
    }
    return QuestReward(
      baseXp: baseXp,
      bonusXp: bonusXp,
      policyVersion: policyVersion,
    );
  }
}

/// An immutable quest generated from a versioned catalog.
final class QuestDefinition {
  QuestDefinition({
    required this.id,
    required this.schemaVersion,
    required this.cadence,
    required this.objective,
    required this.schedule,
    required this.reward,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'must be lower snake case');
    }
    if (schemaVersion != questDefinitionSchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'is not supported',
      );
    }
    if (objective is UnknownQuestObjective) {
      throw ArgumentError.value(objective, 'objective', 'must be supported');
    }
    if (reward.totalXp < 1) {
      throw ArgumentError.value(reward, 'reward', 'must grant positive XP');
    }
  }

  final String id;
  final int schemaVersion;
  final QuestCadence cadence;
  final QuestObjective objective;
  final QuestSchedule schedule;
  final QuestReward reward;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'id': id,
    'cadence': cadence.name,
    'objective': objective.toJson(),
    'schedule': schedule.toJson(),
    'reward': reward.toJson(),
  };

  factory QuestDefinition.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be an object');
    }
    return QuestDefinition(
      id: _requireString(json, 'id'),
      schemaVersion: _requireInt(json, 'schemaVersion'),
      cadence: _cadenceFromName(_requireString(json, 'cadence')),
      objective: QuestObjective.fromJson(json['objective']),
      schedule: QuestSchedule.fromJson(json['schedule']),
      reward: QuestReward.fromJson(json['reward']),
    );
  }
}

QuestCadence _cadenceFromName(String name) {
  for (final cadence in QuestCadence.values) {
    if (cadence.name == name) return cadence;
  }
  throw ArgumentError.value(name, 'cadence', 'is not supported');
}

int _requireInt(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is int) return value;
  throw ArgumentError.value(value, field, 'must be an integer');
}

String _requireString(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is String) return value;
  throw ArgumentError.value(value, field, 'must be a string');
}
