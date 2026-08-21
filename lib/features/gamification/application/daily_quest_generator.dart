import 'dart:convert';

import '../domain/quests/quest_definition.dart';
import '../domain/quests/quest_objective.dart';
import '../domain/quests/quest_schedule.dart';
import '../infrastructure/default_quest_catalog.dart';

/// Caller-fed inputs for one daily generation decision.
final class DailyQuestGenerationSnapshot {
  DailyQuestGenerationSnapshot({
    required this.schedule,
    required this.profileSnapshotKey,
    required List<QuestObjective>? plannedObjectives,
    required this.plannedRest,
    required this.cameraAvailable,
    required this.accountAvailable,
    required this.cloudAvailable,
    required this.isNewProfile,
  }) : plannedObjectives = plannedObjectives == null
           ? null
           : List<QuestObjective>.unmodifiable(plannedObjectives) {
    if (profileSnapshotKey.isEmpty) {
      throw ArgumentError.value(
        profileSnapshotKey,
        'profileSnapshotKey',
        'must not be empty',
      );
    }
  }

  final QuestSchedule schedule;
  final String profileSnapshotKey;
  final List<QuestObjective>? plannedObjectives;
  final bool plannedRest;
  final bool cameraAvailable;
  final bool accountAvailable;
  final bool cloudAvailable;
  final bool isNewProfile;
}

/// A generated daily quest and presentation metadata.
final class GeneratedDailyQuest {
  const GeneratedDailyQuest({
    required this.definition,
    required this.isOptional,
    required this.isShort,
    required this.isRestEligible,
  });

  final QuestDefinition definition;
  final bool isOptional;
  final bool isShort;
  final bool isRestEligible;
}

/// Generates daily quests from a caller-provided daily snapshot.
final class DailyQuestGenerator {
  DailyQuestGenerator({required this.catalog});

  static const int _maximumQuestCount = 3;

  final DailyQuestCatalog catalog;

  List<GeneratedDailyQuest> generate(DailyQuestGenerationSnapshot snapshot) {
    final plannedObjectives = snapshot.plannedObjectives;
    if (snapshot.isNewProfile || plannedObjectives == null) {
      return _fallback(snapshot);
    }

    final candidates =
        catalog.entries
            .where(
              (entry) =>
                  _isAvailable(entry, snapshot) &&
                  _matchesPlan(entry.objective, plannedObjectives),
            )
            .where((entry) => !snapshot.plannedRest || entry.isRestEligible)
            .toList(growable: false)
          ..sort(
            (left, right) => dailyQuestSortKey(
              snapshot,
              left.id,
            ).compareTo(dailyQuestSortKey(snapshot, right.id)),
          );

    if (candidates.isEmpty) {
      return _fallback(snapshot);
    }

    final selected = candidates.take(_maximumQuestCount).toList(growable: true);
    if (!_ensureShortObjective(selected, candidates)) {
      return _fallback(snapshot);
    }
    return List<GeneratedDailyQuest>.unmodifiable(
      selected
          .map(
            (entry) => GeneratedDailyQuest(
              definition: QuestDefinition(
                id: entry.id,
                schemaVersion: questDefinitionSchemaVersion,
                cadence: QuestCadence.daily,
                objective: entry.objective,
                schedule: snapshot.schedule,
                reward: entry.reward,
              ),
              isOptional: snapshot.plannedRest,
              isShort: entry.isShort,
              isRestEligible: entry.isRestEligible,
            ),
          )
          .toList(growable: false),
    );
  }

  bool _ensureShortObjective(
    List<DailyQuestCatalogEntry> selected,
    List<DailyQuestCatalogEntry> candidates,
  ) {
    if (selected.any((entry) => entry.isShort)) return true;
    DailyQuestCatalogEntry? shortCandidate;
    for (final entry in candidates) {
      if (entry.isShort) {
        shortCandidate = entry;
        break;
      }
    }
    if (shortCandidate == null) return false;
    selected[selected.length - 1] = shortCandidate;
    return true;
  }

  bool _isAvailable(
    DailyQuestCatalogEntry entry,
    DailyQuestGenerationSnapshot snapshot,
  ) => entry.requiredCapabilities.every(
    (capability) => switch (capability) {
      QuestCapability.camera => snapshot.cameraAvailable,
      QuestCapability.account => snapshot.accountAvailable,
      QuestCapability.cloud => snapshot.cloudAvailable,
    },
  );

  bool _matchesPlan(
    QuestObjective objective,
    List<QuestObjective> plannedObjectives,
  ) => plannedObjectives.any(
    (planned) => _sameJson(objective.toJson(), planned.toJson()),
  );

  List<GeneratedDailyQuest> _fallback(DailyQuestGenerationSnapshot snapshot) =>
      List<GeneratedDailyQuest>.unmodifiable(<GeneratedDailyQuest>[
        GeneratedDailyQuest(
          definition: QuestDefinition(
            id: 'daily_check_in',
            schemaVersion: questDefinitionSchemaVersion,
            cadence: QuestCadence.daily,
            objective: SkillTagQuestObjective('daily_check_in'),
            schedule: snapshot.schedule,
            reward: QuestReward(baseXp: 5, bonusXp: 0, policyVersion: 1),
          ),
          isOptional: snapshot.plannedRest,
          isShort: true,
          isRestEligible: true,
        ),
      ]);
}

/// Stable UTF-8 seed material for the documented FNV-1a ordering contract.
String dailyQuestSeedMaterial(DailyQuestGenerationSnapshot snapshot) =>
    '${snapshot.schedule.generationEpochDay}|${snapshot.profileSnapshotKey}|${snapshot.schedule.catalogVersion}';

/// 64-bit FNV-1a ordering key for a stable catalog identifier.
int dailyQuestSortKey(DailyQuestGenerationSnapshot snapshot, String catalogId) {
  const offsetBasis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xffffffffffffffff;
  var hash = offsetBasis;
  for (final byte in utf8.encode(
    '${dailyQuestSeedMaterial(snapshot)}|$catalogId',
  )) {
    hash = ((hash ^ byte) * prime) & mask;
  }
  return hash;
}

bool _sameJson(Object? left, Object? right) {
  if (left is Map<String, Object?> && right is Map<String, Object?>) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_sameJson(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List<Object?> && right is List<Object?>) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameJson(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}
