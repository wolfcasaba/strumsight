import '../data/reward_ledger_repository.dart';
import '../domain/achievements/achievement_catalog.dart';
import '../domain/achievements/achievement_definition.dart';
import '../domain/achievements/achievement_progress.dart';
import '../domain/activity/learning_activity_event.dart';
import '../domain/rewards/reward_ledger_entry.dart';
import '../domain/rewards/reward_reason.dart';
import 'achievement_index.dart';

/// Version stamped on zero-XP achievement audit receipts.
const int achievementEvaluatorPolicyVersion = 1;

/// Caller-supplied, immutable evaluation evidence for one canonical event.
final class AchievementEvaluationEvidence {
  AchievementEvaluationEvidence({
    required this.event,
    required Map<AchievementMetric, num> metrics,
  }) : metrics = Map<AchievementMetric, num>.unmodifiable(metrics) {
    for (final entry in this.metrics.entries) {
      if (!_isExplicitMetric(entry.key) || !entry.value.isFinite) {
        throw ArgumentError.value(
          entry.value,
          'metrics',
          'must contain finite explicit XP metrics only',
        );
      }
    }
  }

  final LearningActivityEvent event;
  final Map<AchievementMetric, num> metrics;

  num? valueFor(AchievementMetric metric) => switch (metric) {
    AchievementMetric.eventCount => 1,
    AchievementMetric.durationSeconds =>
      event.duration.inMicroseconds / Duration.microsecondsPerSecond,
    AchievementMetric.score => event.score,
    _ => metrics[metric],
  };
}

/// Stable diagnostic kinds emitted when an objective cannot be evaluated.
enum AchievementEvaluationDiagnosticCode {
  unknownObjective,
  missingMetric,
  excludedByBackfill,
}

/// Immutable diagnostic for one fail-closed achievement evaluation path.
final class AchievementEvaluationDiagnostic {
  const AchievementEvaluationDiagnostic({
    required this.achievementId,
    required this.code,
  });

  final String achievementId;
  final AchievementEvaluationDiagnosticCode code;
}

/// Immutable reference to a receipt that unlocked an achievement.
final class AchievementUnlock {
  const AchievementUnlock({
    required this.achievementId,
    required this.rewardLedgerEntryId,
    required this.completedAt,
  });

  final String achievementId;
  final String rewardLedgerEntryId;
  final DateTime completedAt;
}

/// Immutable projection output for one incremental or rebuild evaluation.
final class AchievementEvaluationResult {
  AchievementEvaluationResult({
    required Map<String, AchievementProgress> progressByAchievement,
    required List<AchievementUnlock> unlocked,
    required List<AchievementEvaluationDiagnostic> diagnostics,
    required this.evaluatedAchievementCount,
    this.skippedBackfillEventCount = 0,
  }) : progressByAchievement = Map<String, AchievementProgress>.unmodifiable(
         progressByAchievement,
       ),
       unlocked = List<AchievementUnlock>.unmodifiable(unlocked),
       diagnostics = List<AchievementEvaluationDiagnostic>.unmodifiable(
         diagnostics,
       );

  final Map<String, AchievementProgress> progressByAchievement;
  final List<AchievementUnlock> unlocked;
  final List<AchievementEvaluationDiagnostic> diagnostics;
  final int evaluatedAchievementCount;
  final int skippedBackfillEventCount;
}

/// Projects indexed achievement progress and persists only idempotent receipts.
final class AchievementEvaluator {
  AchievementEvaluator({
    required this.catalog,
    required this.ledger,
    this.backfillWindowDays = 30,
  }) : index = AchievementIndex(catalog) {
    if (backfillWindowDays < 0) {
      throw ArgumentError.value(
        backfillWindowDays,
        'backfillWindowDays',
        'must not be negative',
      );
    }
  }

  final AchievementCatalog catalog;
  final RewardLedgerRepository ledger;
  final int backfillWindowDays;
  final AchievementIndex index;

  /// Evaluates only definitions indexed for [evidence]'s canonical event kind.
  Future<AchievementEvaluationResult> evaluate({
    required AchievementEvaluationEvidence evidence,
    required Iterable<AchievementEvaluationEvidence> history,
  }) => _evaluateDefinitions(
    definitions: index.candidatesFor(_eventKindFor(evidence.event)),
    trigger: evidence,
    history: List<AchievementEvaluationEvidence>.unmodifiable(history),
  );

  /// Rebuilds the complete projection from the caller-provided canonical history.
  Future<AchievementEvaluationResult> rebuild({
    required Iterable<AchievementEvaluationEvidence> history,
  }) async {
    final snapshot = List<AchievementEvaluationEvidence>.unmodifiable(history);
    final progress = <String, AchievementProgress>{};
    final unlocked = <AchievementUnlock>[];
    final diagnostics = <AchievementEvaluationDiagnostic>[];
    for (var index = 0; index < snapshot.length; index++) {
      final result = await evaluate(
        evidence: snapshot[index],
        history: snapshot.sublist(0, index + 1),
      );
      progress.addAll(result.progressByAchievement);
      unlocked.addAll(result.unlocked);
      _addDiagnostics(diagnostics, result.diagnostics);
    }
    for (final definition in catalog.definitions) {
      progress.putIfAbsent(
        definition.id,
        () => AchievementProgress(
          achievementId: definition.id,
          catalogVersion: catalog.contentVersion,
          value: 0,
        ),
      );
    }
    return AchievementEvaluationResult(
      progressByAchievement: progress,
      unlocked: unlocked,
      diagnostics: diagnostics,
      evaluatedAchievementCount: catalog.definitions.length,
    );
  }

  /// Rebuilds only history at or after the inclusive, caller-supplied UTC cutoff.
  Future<AchievementEvaluationResult> backfill({
    required Iterable<AchievementEvaluationEvidence> history,
    required DateTime anchor,
  }) async {
    if (!anchor.isUtc) {
      throw ArgumentError.value(anchor, 'anchor', 'must be UTC');
    }
    final cutoff = anchor.subtract(Duration(days: backfillWindowDays));
    final retained = <AchievementEvaluationEvidence>[];
    var skipped = 0;
    for (final evidence in history) {
      if (evidence.event.occurredAt.isBefore(cutoff)) {
        skipped++;
      } else {
        retained.add(evidence);
      }
    }
    final result = await rebuild(history: retained);
    final diagnostics = <AchievementEvaluationDiagnostic>[
      ...result.diagnostics,
    ];
    if (skipped > 0) {
      diagnostics.addAll(
        catalog.definitions.map(
          (definition) => AchievementEvaluationDiagnostic(
            achievementId: definition.id,
            code: AchievementEvaluationDiagnosticCode.excludedByBackfill,
          ),
        ),
      );
    }
    return AchievementEvaluationResult(
      progressByAchievement: result.progressByAchievement,
      unlocked: result.unlocked,
      diagnostics: diagnostics,
      evaluatedAchievementCount: result.evaluatedAchievementCount,
      skippedBackfillEventCount: skipped,
    );
  }

  Future<AchievementEvaluationResult> _evaluateDefinitions({
    required List<AchievementDefinition> definitions,
    required AchievementEvaluationEvidence trigger,
    required List<AchievementEvaluationEvidence> history,
  }) async {
    final progress = <String, AchievementProgress>{};
    final unlocked = <AchievementUnlock>[];
    final diagnostics = <AchievementEvaluationDiagnostic>[];
    for (final definition in definitions) {
      final state = _objectiveState(definition.objectives, history);
      if (state.diagnostic != null) {
        _addDiagnostics(diagnostics, <AchievementEvaluationDiagnostic>[
          AchievementEvaluationDiagnostic(
            achievementId: definition.id,
            code: state.diagnostic!,
          ),
        ]);
        progress[definition.id] = _progress(definition, state.value);
        continue;
      }
      final existing = _receiptFor(definition.id);
      if (existing != null) {
        progress[definition.id] = _progress(
          definition,
          state.value,
          completedAt: existing.createdAt,
          rewardLedgerEntryId: existing.ledgerId,
        );
        continue;
      }
      if (state.value < 1 || !_tierPrerequisitesCompleted(definition)) {
        progress[definition.id] = _progress(definition, state.value);
        continue;
      }
      final receipt = _receipt(definition.id, trigger.event);
      final appended = await ledger.appendIfAbsent(receipt);
      if (appended) {
        unlocked.add(
          AchievementUnlock(
            achievementId: definition.id,
            rewardLedgerEntryId: receipt.ledgerId,
            completedAt: receipt.createdAt,
          ),
        );
        progress[definition.id] = _progress(
          definition,
          state.value,
          completedAt: receipt.createdAt,
          rewardLedgerEntryId: receipt.ledgerId,
        );
      } else {
        final persisted = _receiptFor(definition.id);
        progress[definition.id] = _progress(
          definition,
          state.value,
          completedAt: persisted?.createdAt,
          rewardLedgerEntryId: persisted?.ledgerId,
        );
      }
    }
    return AchievementEvaluationResult(
      progressByAchievement: progress,
      unlocked: unlocked,
      diagnostics: diagnostics,
      evaluatedAchievementCount: definitions.length,
    );
  }

  bool _tierPrerequisitesCompleted(AchievementDefinition definition) =>
      definition.tierPrerequisiteIds.every((id) => _receiptFor(id) != null);

  RewardLedgerEntry? _receiptFor(String achievementId) {
    final prefix = 'achievement:$achievementId:';
    String? cursor;
    do {
      final page = ledger.readPage(limit: 100, cursor: cursor);
      for (final entry in page.entries) {
        if (entry.sourceEventId.startsWith(prefix)) return entry;
      }
      if (page.nextCursor != null && page.nextCursor == cursor) {
        throw StateError('ledger page cursor did not advance');
      }
      cursor = page.nextCursor;
    } while (cursor != null);
    return null;
  }
}

AchievementProgress _progress(
  AchievementDefinition definition,
  num value, {
  DateTime? completedAt,
  String? rewardLedgerEntryId,
}) => AchievementProgress(
  achievementId: definition.id,
  catalogVersion: definition.version,
  value: value,
  completedAt: completedAt,
  rewardLedgerEntryId: rewardLedgerEntryId,
);

RewardLedgerEntry _receipt(String achievementId, LearningActivityEvent event) {
  final sourceEventId = 'achievement:$achievementId:${event.eventId}';
  return RewardLedgerEntry(
    ledgerId: sourceEventId,
    sourceEventId: sourceEventId,
    createdAt: event.occurredAt,
    schemaVersion: rewardLedgerEntrySchemaVersion,
    policyVersion: achievementEvaluatorPolicyVersion,
    baseXp: 0,
    bonusXp: 0,
    totalXp: 0,
    reasonCodes: const <RewardReason>[RewardReason.achievementUnlocked],
  );
}

_ObjectiveState _objectiveState(
  Iterable<AchievementObjective> objectives,
  List<AchievementEvaluationEvidence> history,
) {
  var value = 1.0;
  for (final objective in objectives) {
    final state = _evaluateObjective(objective, history);
    if (state.diagnostic != null) return state;
    if (state.value < value) value = state.value;
  }
  return _ObjectiveState(value: value);
}

_ObjectiveState _evaluateObjective(
  AchievementObjective objective,
  List<AchievementEvaluationEvidence> history,
) => switch (objective) {
  CountAchievementObjective(:final eventKind, :final target) => _countState(
    history
        .where((evidence) => _eventKindFor(evidence.event) == eventKind)
        .length,
    target,
  ),
  ThresholdAchievementObjective(
    :final eventKind,
    :final metric,
    :final minimum,
  ) =>
    _thresholdState(eventKind, metric, minimum, history),
  DistinctAchievementObjective(:final eventKind, :final target) => _countState(
    history
        .where((evidence) => _eventKindFor(evidence.event) == eventKind)
        .map((evidence) => evidence.event.source)
        .toSet()
        .length,
    target,
  ),
  SequenceAchievementObjective(:final eventKinds) => _sequenceState(
    eventKinds,
    history,
  ),
  CompoundAchievementObjective(:final objectives) => _objectiveState(
    objectives,
    history,
  ),
  UnknownAchievementObjective() => const _ObjectiveState(
    value: 0,
    diagnostic: AchievementEvaluationDiagnosticCode.unknownObjective,
  ),
};

_ObjectiveState _countState(num count, num target) =>
    _ObjectiveState(value: (count / target).clamp(0, 1).toDouble());

_ObjectiveState _thresholdState(
  AchievementEventKind eventKind,
  AchievementMetric metric,
  num minimum,
  List<AchievementEvaluationEvidence> history,
) {
  num? maximum;
  for (final evidence in history) {
    if (_eventKindFor(evidence.event) != eventKind) continue;
    final value = evidence.valueFor(metric);
    if (value == null) {
      return const _ObjectiveState(
        value: 0,
        diagnostic: AchievementEvaluationDiagnosticCode.missingMetric,
      );
    }
    if (maximum == null || value > maximum) maximum = value;
  }
  if (maximum == null) return const _ObjectiveState(value: 0);
  if (minimum == 0) return const _ObjectiveState(value: 1);
  return _ObjectiveState(value: (maximum / minimum).clamp(0, 1).toDouble());
}

_ObjectiveState _sequenceState(
  List<AchievementEventKind> sequence,
  List<AchievementEvaluationEvidence> history,
) {
  var matched = 0;
  for (final evidence in history) {
    if (matched < sequence.length &&
        _eventKindFor(evidence.event) == sequence[matched]) {
      matched++;
    }
  }
  return _countState(matched, sequence.length);
}

AchievementEventKind _eventKindFor(LearningActivityEvent event) =>
    switch (event) {
      PracticeActivityEvent() => AchievementEventKind.practice,
      SongActivityEvent() => AchievementEventKind.song,
      AnalysisActivityEvent() => AchievementEventKind.analysis,
      PlanActivityEvent() => AchievementEventKind.plan,
      TutorActivityEvent() => AchievementEventKind.tutor,
      VisionActivityEvent() => AchievementEventKind.vision,
    };

bool _isExplicitMetric(AchievementMetric metric) => switch (metric) {
  AchievementMetric.baseXp ||
  AchievementMetric.durationXp ||
  AchievementMetric.qualityXp ||
  AchievementMetric.improvementXp ||
  AchievementMetric.diversityXp ||
  AchievementMetric.totalXp => true,
  AchievementMetric.eventCount ||
  AchievementMetric.durationSeconds ||
  AchievementMetric.score => false,
};

void _addDiagnostics(
  List<AchievementEvaluationDiagnostic> target,
  Iterable<AchievementEvaluationDiagnostic> incoming,
) {
  for (final diagnostic in incoming) {
    if (!target.any(
      (existing) =>
          existing.achievementId == diagnostic.achievementId &&
          existing.code == diagnostic.code,
    )) {
      target.add(diagnostic);
    }
  }
}

final class _ObjectiveState {
  const _ObjectiveState({required this.value, this.diagnostic});

  final double value;
  final AchievementEvaluationDiagnosticCode? diagnostic;
}
