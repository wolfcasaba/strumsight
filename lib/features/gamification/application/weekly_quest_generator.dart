import 'dart:convert';

import '../domain/achievements/achievement_definition.dart';
import '../domain/quests/quest_definition.dart';
import '../domain/quests/quest_objective.dart';
import '../domain/quests/quest_schedule.dart';

/// The supported objective families for generated weekly quests.
enum WeeklyQuestObjectiveKind {
  activeDays,
  planBlock,
  modeDiversity,
  improvement,
}

/// Caller-provided inputs for one pure weekly quest projection.
final class WeeklyQuestGenerationSnapshot {
  WeeklyQuestGenerationSnapshot({
    required this.schedule,
    required this.profileSnapshotKey,
    required this.availableDays,
    required this.availableMinutes,
    required this.baselineWeeklyMinutes,
    required this.previousCompletedUnits,
    required this.observedCompletedUnits,
    required List<WeeklyQuestCandidate> candidates,
    required this.improvementMeasurementAvailable,
  }) : candidates = List<WeeklyQuestCandidate>.unmodifiable(candidates) {
    if (profileSnapshotKey.isEmpty) {
      throw ArgumentError.value(
        profileSnapshotKey,
        'profileSnapshotKey',
        'must not be empty',
      );
    }
    if (availableDays < 0 || availableMinutes < 0) {
      throw ArgumentError('availability must not be negative');
    }
    if (baselineWeeklyMinutes < 1) {
      throw ArgumentError.value(
        baselineWeeklyMinutes,
        'baselineWeeklyMinutes',
        'must be positive',
      );
    }
    if (previousCompletedUnits < 0 || observedCompletedUnits < 0) {
      throw ArgumentError('completed units must not be negative');
    }
    if (this.candidates.map((candidate) => candidate.id).toSet().length !=
        this.candidates.length) {
      throw ArgumentError.value(
        candidates,
        'candidates',
        'must have unique IDs',
      );
    }
  }

  final QuestSchedule schedule;
  final String profileSnapshotKey;
  final int availableDays;
  final int availableMinutes;
  final int baselineWeeklyMinutes;
  final int previousCompletedUnits;
  final int observedCompletedUnits;
  final List<WeeklyQuestCandidate> candidates;
  final bool improvementMeasurementAvailable;
}

/// A stable, typed catalog entry for weekly quest generation.
final class WeeklyQuestCandidate {
  WeeklyQuestCandidate({
    required this.id,
    required this.kind,
    required this.objective,
    required this.baseTargetUnits,
    required this.reward,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'must be lower snake case');
    }
    if (baseTargetUnits < 1) {
      throw ArgumentError.value(
        baseTargetUnits,
        'baseTargetUnits',
        'must be positive',
      );
    }
    if (!_matchesKind(kind, objective)) {
      throw ArgumentError.value(
        objective,
        'objective',
        'must match the supplied weekly quest kind',
      );
    }
  }

  final String id;
  final WeeklyQuestObjectiveKind kind;
  final QuestObjective objective;
  final int baseTargetUnits;
  final QuestReward reward;
}

/// Inputs retained to explain a generated target without presentation text.
final class WeeklyQuestTargetDerivation {
  const WeeklyQuestTargetDerivation({
    required this.baseTargetUnits,
    required this.availableMinutes,
    required this.baselineWeeklyMinutes,
    required this.availableDays,
  });

  final int baseTargetUnits;
  final int availableMinutes;
  final int baselineWeeklyMinutes;
  final int availableDays;
}

/// Monotonic progress facts for one generated weekly quest.
final class WeeklyQuestProgressProjection {
  const WeeklyQuestProgressProjection({
    required this.targetUnits,
    required this.completedUnits,
  });

  final int targetUnits;
  final int completedUnits;

  bool get isCompleted => completedUnits >= targetUnits;
}

/// Closed status used by a presentation layer to render a weekly rollover.
enum WeeklyQuestRolloverStatus { completed, stillOpen }

/// Language-neutral facts for a weekly rollover.
final class WeeklyQuestRollover {
  const WeeklyQuestRollover({
    required this.status,
    required this.targetUnits,
    required this.completedUnits,
  });

  final WeeklyQuestRolloverStatus status;
  final int targetUnits;
  final int completedUnits;
}

/// A deterministic weekly quest and the facts used to explain its state.
final class GeneratedWeeklyQuest {
  const GeneratedWeeklyQuest({
    required this.definition,
    required this.candidate,
    required this.targetDerivation,
    required this.progress,
    required this.rollover,
  });

  final QuestDefinition definition;
  final WeeklyQuestCandidate candidate;
  final WeeklyQuestTargetDerivation targetDerivation;
  final WeeklyQuestProgressProjection progress;
  final WeeklyQuestRollover rollover;
}

/// Generates a weekly quest from caller-fed availability and measurements.
final class WeeklyQuestGenerator {
  static const int _maximumRequiredActiveDays = 5;

  GeneratedWeeklyQuest? generate(WeeklyQuestGenerationSnapshot snapshot) {
    if (snapshot.availableDays == 0 || snapshot.availableMinutes == 0) {
      return null;
    }

    final eligibleCandidates =
        snapshot.candidates
            .where(
              (candidate) =>
                  candidate.kind != WeeklyQuestObjectiveKind.improvement ||
                  snapshot.improvementMeasurementAvailable,
            )
            .toList(growable: false)
          ..sort((left, right) {
            final order = weeklyQuestSortKey(
              snapshot,
              left.id,
            ).compareTo(weeklyQuestSortKey(snapshot, right.id));
            return order == 0 ? left.id.compareTo(right.id) : order;
          });
    if (eligibleCandidates.isEmpty) return null;

    final candidate = eligibleCandidates.first;
    final scaledTarget = _ceilScale(
      baseTargetUnits: candidate.baseTargetUnits,
      availableMinutes: snapshot.availableMinutes,
      baselineWeeklyMinutes: snapshot.baselineWeeklyMinutes,
    );
    final targetUnits = candidate.kind == WeeklyQuestObjectiveKind.activeDays
        ? _min(scaledTarget, snapshot.availableDays, _maximumRequiredActiveDays)
        : scaledTarget < 1
        ? 1
        : scaledTarget;
    final completedUnits = _max(
      snapshot.previousCompletedUnits,
      snapshot.observedCompletedUnits,
    );
    final progress = WeeklyQuestProgressProjection(
      targetUnits: targetUnits,
      completedUnits: completedUnits,
    );

    return GeneratedWeeklyQuest(
      definition: QuestDefinition(
        id: candidate.id,
        schemaVersion: questDefinitionSchemaVersion,
        cadence: QuestCadence.weekly,
        objective: candidate.objective,
        schedule: snapshot.schedule,
        reward: candidate.reward,
      ),
      candidate: candidate,
      targetDerivation: WeeklyQuestTargetDerivation(
        baseTargetUnits: candidate.baseTargetUnits,
        availableMinutes: snapshot.availableMinutes,
        baselineWeeklyMinutes: snapshot.baselineWeeklyMinutes,
        availableDays: snapshot.availableDays,
      ),
      progress: progress,
      rollover: WeeklyQuestRollover(
        status: progress.isCompleted
            ? WeeklyQuestRolloverStatus.completed
            : WeeklyQuestRolloverStatus.stillOpen,
        targetUnits: targetUnits,
        completedUnits: completedUnits,
      ),
    );
  }
}

/// Stable UTF-8 material used for the weekly catalog ordering contract.
String weeklyQuestSeedMaterial(WeeklyQuestGenerationSnapshot snapshot) =>
    '${snapshot.schedule.generationEpochDay}|${snapshot.profileSnapshotKey}|${snapshot.schedule.catalogVersion}';

/// 64-bit FNV-1a ordering key for a weekly candidate identifier.
int weeklyQuestSortKey(
  WeeklyQuestGenerationSnapshot snapshot,
  String candidateId,
) {
  const offsetBasis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xffffffffffffffff;
  var hash = offsetBasis;
  for (final byte in utf8.encode(
    '${weeklyQuestSeedMaterial(snapshot)}|$candidateId',
  )) {
    hash = ((hash ^ byte) * prime) & mask;
  }
  return hash;
}

bool _matchesKind(WeeklyQuestObjectiveKind kind, QuestObjective objective) =>
    switch (kind) {
      WeeklyQuestObjectiveKind.activeDays =>
        objective is MetricQuestObjective &&
            objective.metric == AchievementMetric.eventCount,
      WeeklyQuestObjectiveKind.planBlock =>
        objective is PlanBlockQuestObjective,
      WeeklyQuestObjectiveKind.modeDiversity =>
        objective is MetricQuestObjective &&
            objective.metric == AchievementMetric.diversityXp,
      WeeklyQuestObjectiveKind.improvement =>
        objective is MetricQuestObjective &&
            objective.metric == AchievementMetric.improvementXp,
    };

int _ceilScale({
  required int baseTargetUnits,
  required int availableMinutes,
  required int baselineWeeklyMinutes,
}) =>
    (baseTargetUnits * availableMinutes + baselineWeeklyMinutes - 1) ~/
    baselineWeeklyMinutes;

int _min(int first, int second, int third) => first < second
    ? (first < third ? first : third)
    : (second < third ? second : third);

int _max(int first, int second) => first > second ? first : second;
