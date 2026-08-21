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

/// Maximum caller-supplied history events accepted in one projection snapshot.
const int achievementEvaluatorHistoryLimit = 10000;

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

/// Stable diagnostic kinds emitted when evaluation must fail closed.
enum AchievementEvaluationDiagnosticCode {
  unknownObjective,
  missingMetric,
  excludedByBackfill,
  conflictingEventPayload,
  invalidAchievementReceipt,
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
  }) async {
    final normalized = _normalizeHistory(history);
    final definitions = index.candidatesForEvent(_eventKindFor(evidence.event));
    final receiptIndex = _buildReceiptIndex();
    return _evaluateDefinitions(
      definitions: definitions,
      trigger: evidence,
      history: normalized,
      receiptIndex: receiptIndex,
    );
  }

  /// Rebuilds a deterministic projection with one history pass and one receipt index.
  Future<AchievementEvaluationResult> rebuild({
    required Iterable<AchievementEvaluationEvidence> history,
  }) async {
    final normalized = _normalizeHistory(history);
    final receiptIndex = _buildReceiptIndex();
    final reducers = <String, _ObjectiveReducer>{
      for (final definition in catalog.definitions)
        definition.id: _ObjectiveReducer(definition.objectives),
    };
    final unlocked = <AchievementUnlock>[];
    final diagnostics = <AchievementEvaluationDiagnostic>[];

    if (normalized.hasConflict) {
      for (final definition in catalog.definitions) {
        _addDiagnostic(
          diagnostics,
          definition.id,
          AchievementEvaluationDiagnosticCode.conflictingEventPayload,
        );
      }
      return _resultForReducers(
        reducers: reducers,
        receiptIndex: receiptIndex,
        unlocked: unlocked,
        diagnostics: diagnostics,
      );
    }

    for (final evidence in normalized.events) {
      for (final definition in index.candidatesForEvent(
        _eventKindFor(evidence.event),
      )) {
        final reducer = reducers[definition.id]!;
        reducer.add(evidence);
        await _unlockIfEligible(
          definition: definition,
          state: reducer.state,
          trigger: evidence,
          receiptIndex: receiptIndex,
          unlocked: unlocked,
          diagnostics: diagnostics,
        );
      }
    }

    return _resultForReducers(
      reducers: reducers,
      receiptIndex: receiptIndex,
      unlocked: unlocked,
      diagnostics: diagnostics,
    );
  }

  /// Rebuilds only history within the inclusive caller-supplied UTC window.
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
      final occurredAt = evidence.event.occurredAt;
      if (occurredAt.isBefore(cutoff) || occurredAt.isAfter(anchor)) {
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
      for (final definition in catalog.definitions) {
        _addDiagnostic(
          diagnostics,
          definition.id,
          AchievementEvaluationDiagnosticCode.excludedByBackfill,
        );
      }
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
    required _NormalizedHistory history,
    required _ReceiptIndex receiptIndex,
  }) async {
    final progress = <String, AchievementProgress>{};
    final unlocked = <AchievementUnlock>[];
    final diagnostics = <AchievementEvaluationDiagnostic>[];
    for (final definition in definitions) {
      if (history.hasConflict) {
        _addDiagnostic(
          diagnostics,
          definition.id,
          AchievementEvaluationDiagnosticCode.conflictingEventPayload,
        );
        progress[definition.id] = _progress(definition, 0);
        continue;
      }
      final state = _objectiveState(definition.objectives, history.events);
      if (state.diagnostic != null) {
        _addDiagnostic(diagnostics, definition.id, state.diagnostic!);
        progress[definition.id] = _progress(definition, state.value);
        continue;
      }
      if (receiptIndex.isInvalid(definition.id)) {
        _addDiagnostic(
          diagnostics,
          definition.id,
          AchievementEvaluationDiagnosticCode.invalidAchievementReceipt,
        );
        progress[definition.id] = _progress(definition, state.value);
        continue;
      }
      final existing = receiptIndex.validFor(definition.id);
      if (existing != null) {
        progress[definition.id] = _progress(
          definition,
          state.value,
          completedAt: existing.createdAt,
          rewardLedgerEntryId: existing.ledgerId,
        );
        continue;
      }
      if (state.value < 1) {
        progress[definition.id] = _progress(definition, state.value);
        continue;
      }
      if (_hasInvalidTierPrerequisite(definition, receiptIndex)) {
        _addDiagnostic(
          diagnostics,
          definition.id,
          AchievementEvaluationDiagnosticCode.invalidAchievementReceipt,
        );
        progress[definition.id] = _progress(definition, state.value);
        continue;
      }
      if (!_tierPrerequisitesCompleted(definition, receiptIndex)) {
        progress[definition.id] = _progress(definition, state.value);
        continue;
      }
      final receipt = _receipt(definition.id, trigger.event);
      final appended = await ledger.appendIfAbsent(receipt);
      if (appended) {
        receiptIndex.addValid(definition.id, receipt);
        unlocked.add(_unlock(definition.id, receipt));
        progress[definition.id] = _progress(
          definition,
          state.value,
          completedAt: receipt.createdAt,
          rewardLedgerEntryId: receipt.ledgerId,
        );
      } else {
        final persisted = _buildReceiptIndex();
        final entry = persisted.validFor(definition.id);
        if (persisted.isInvalid(definition.id) || entry == null) {
          _addDiagnostic(
            diagnostics,
            definition.id,
            AchievementEvaluationDiagnosticCode.invalidAchievementReceipt,
          );
          progress[definition.id] = _progress(definition, state.value);
        } else {
          progress[definition.id] = _progress(
            definition,
            state.value,
            completedAt: entry.createdAt,
            rewardLedgerEntryId: entry.ledgerId,
          );
        }
      }
    }
    return AchievementEvaluationResult(
      progressByAchievement: progress,
      unlocked: unlocked,
      diagnostics: diagnostics,
      evaluatedAchievementCount: definitions.length,
    );
  }

  Future<void> _unlockIfEligible({
    required AchievementDefinition definition,
    required _ObjectiveState state,
    required AchievementEvaluationEvidence trigger,
    required _ReceiptIndex receiptIndex,
    required List<AchievementUnlock> unlocked,
    required List<AchievementEvaluationDiagnostic> diagnostics,
  }) async {
    if (state.diagnostic != null) {
      _addDiagnostic(diagnostics, definition.id, state.diagnostic!);
      return;
    }
    if (receiptIndex.isInvalid(definition.id)) {
      _addDiagnostic(
        diagnostics,
        definition.id,
        AchievementEvaluationDiagnosticCode.invalidAchievementReceipt,
      );
      return;
    }
    if (receiptIndex.validFor(definition.id) != null || state.value < 1) return;
    if (_hasInvalidTierPrerequisite(definition, receiptIndex)) {
      _addDiagnostic(
        diagnostics,
        definition.id,
        AchievementEvaluationDiagnosticCode.invalidAchievementReceipt,
      );
      return;
    }
    if (!_tierPrerequisitesCompleted(definition, receiptIndex)) return;

    final receipt = _receipt(definition.id, trigger.event);
    if (await ledger.appendIfAbsent(receipt)) {
      receiptIndex.addValid(definition.id, receipt);
      unlocked.add(_unlock(definition.id, receipt));
      return;
    }
    final persisted = _buildReceiptIndex();
    final entry = persisted.validFor(definition.id);
    if (persisted.isInvalid(definition.id) || entry == null) {
      _addDiagnostic(
        diagnostics,
        definition.id,
        AchievementEvaluationDiagnosticCode.invalidAchievementReceipt,
      );
    } else {
      receiptIndex.addValid(definition.id, entry);
    }
  }

  AchievementEvaluationResult _resultForReducers({
    required Map<String, _ObjectiveReducer> reducers,
    required _ReceiptIndex receiptIndex,
    required List<AchievementUnlock> unlocked,
    required List<AchievementEvaluationDiagnostic> diagnostics,
  }) {
    final progress = <String, AchievementProgress>{};
    for (final definition in catalog.definitions) {
      final state = reducers[definition.id]!.state;
      if (state.diagnostic != null) {
        _addDiagnostic(diagnostics, definition.id, state.diagnostic!);
      }
      if (receiptIndex.isInvalid(definition.id)) {
        _addDiagnostic(
          diagnostics,
          definition.id,
          AchievementEvaluationDiagnosticCode.invalidAchievementReceipt,
        );
      }
      final receipt = receiptIndex.validFor(definition.id);
      progress[definition.id] = _progress(
        definition,
        state.value,
        completedAt: receipt?.createdAt,
        rewardLedgerEntryId: receipt?.ledgerId,
      );
    }
    return AchievementEvaluationResult(
      progressByAchievement: progress,
      unlocked: unlocked,
      diagnostics: diagnostics,
      evaluatedAchievementCount: catalog.definitions.length,
    );
  }

  bool _tierPrerequisitesCompleted(
    AchievementDefinition definition,
    _ReceiptIndex receiptIndex,
  ) {
    for (final id in definition.tierPrerequisiteIds) {
      if (receiptIndex.isInvalid(id) || receiptIndex.validFor(id) == null) {
        return false;
      }
    }
    return true;
  }

  bool _hasInvalidTierPrerequisite(
    AchievementDefinition definition,
    _ReceiptIndex receiptIndex,
  ) => definition.tierPrerequisiteIds.any(receiptIndex.isInvalid);

  _ReceiptIndex _buildReceiptIndex() {
    final index = _ReceiptIndex(catalog.definitions);
    String? cursor;
    do {
      final page = ledger.readPage(limit: 100, cursor: cursor);
      for (final entry in page.entries) {
        index.add(entry);
      }
      if (page.nextCursor != null && page.nextCursor == cursor) {
        throw StateError('ledger page cursor did not advance');
      }
      cursor = page.nextCursor;
    } while (cursor != null);
    return index;
  }

  AchievementProgress _progress(
    AchievementDefinition definition,
    num value, {
    DateTime? completedAt,
    String? rewardLedgerEntryId,
  }) => AchievementProgress(
    achievementId: definition.id,
    catalogVersion: catalog.contentVersion,
    value: value,
    completedAt: completedAt,
    rewardLedgerEntryId: rewardLedgerEntryId,
  );
}

RewardLedgerEntry _receipt(String achievementId, LearningActivityEvent event) {
  final sourceEventId = 'achievement:$achievementId';
  return RewardLedgerEntry(
    ledgerId: '$sourceEventId:${event.eventId}',
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

AchievementUnlock _unlock(String achievementId, RewardLedgerEntry receipt) =>
    AchievementUnlock(
      achievementId: achievementId,
      rewardLedgerEntryId: receipt.ledgerId,
      completedAt: receipt.createdAt,
    );

_NormalizedHistory _normalizeHistory(
  Iterable<AchievementEvaluationEvidence> history,
) {
  final input = List<AchievementEvaluationEvidence>.of(history);
  if (input.length > achievementEvaluatorHistoryLimit) {
    throw ArgumentError.value(
      input.length,
      'history',
      'must contain at most $achievementEvaluatorHistoryLimit events',
    );
  }
  final byId = <String, AchievementEvaluationEvidence>{};
  var hasConflict = false;
  for (final evidence in input) {
    final existing = byId[evidence.event.eventId];
    if (existing == null) {
      byId[evidence.event.eventId] = evidence;
    } else if (!_sameEvidence(existing, evidence)) {
      hasConflict = true;
    }
  }
  final events = byId.values.toList()
    ..sort((left, right) {
      final timeOrder = left.event.occurredAt.compareTo(right.event.occurredAt);
      return timeOrder != 0
          ? timeOrder
          : left.event.eventId.compareTo(right.event.eventId);
    });
  return _NormalizedHistory(events: events, hasConflict: hasConflict);
}

bool _sameEvidence(
  AchievementEvaluationEvidence left,
  AchievementEvaluationEvidence right,
) {
  if (left.event != right.event ||
      left.metrics.length != right.metrics.length) {
    return false;
  }
  for (final entry in left.metrics.entries) {
    if (right.metrics[entry.key] != entry.value) return false;
  }
  return true;
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

void _addDiagnostic(
  List<AchievementEvaluationDiagnostic> target,
  String achievementId,
  AchievementEvaluationDiagnosticCode code,
) {
  if (!target.any(
    (existing) =>
        existing.achievementId == achievementId && existing.code == code,
  )) {
    target.add(
      AchievementEvaluationDiagnostic(achievementId: achievementId, code: code),
    );
  }
}

final class _NormalizedHistory {
  _NormalizedHistory({
    required List<AchievementEvaluationEvidence> events,
    required this.hasConflict,
  }) : events = List<AchievementEvaluationEvidence>.unmodifiable(events);

  final List<AchievementEvaluationEvidence> events;
  final bool hasConflict;
}

final class _ReceiptIndex {
  _ReceiptIndex(Iterable<AchievementDefinition> definitions)
    : _ids = definitions.map((definition) => definition.id).toSet();

  final Set<String> _ids;
  final Map<String, RewardLedgerEntry> _valid = <String, RewardLedgerEntry>{};
  final Set<String> _invalid = <String>{};

  void add(RewardLedgerEntry entry) {
    for (final id in _ids) {
      final source = 'achievement:$id';
      final ledgerPrefix = '$source:';
      final ownsNamespace =
          entry.sourceEventId == source ||
          entry.sourceEventId.startsWith(ledgerPrefix) ||
          entry.ledgerId.startsWith(ledgerPrefix);
      if (!ownsNamespace) continue;
      if (entry.sourceEventId != source || !_isAuthenticReceipt(entry, id)) {
        _invalid.add(id);
        continue;
      }
      if (_valid.containsKey(id)) {
        _invalid.add(id);
      } else {
        _valid[id] = entry;
      }
    }
  }

  void addValid(String id, RewardLedgerEntry entry) => _valid[id] = entry;

  RewardLedgerEntry? validFor(String id) =>
      _invalid.contains(id) ? null : _valid[id];

  bool isInvalid(String id) => _invalid.contains(id);
}

bool _isAuthenticReceipt(RewardLedgerEntry entry, String achievementId) =>
    entry.ledgerId.startsWith('achievement:$achievementId:') &&
    entry.ledgerId.length > 'achievement:$achievementId:'.length &&
    entry.schemaVersion == rewardLedgerEntrySchemaVersion &&
    entry.policyVersion == achievementEvaluatorPolicyVersion &&
    entry.baseXp == 0 &&
    entry.bonusXp == 0 &&
    entry.totalXp == 0 &&
    entry.reasonCodes.length == 1 &&
    entry.reasonCodes.single == RewardReason.achievementUnlocked;

final class _ObjectiveReducer {
  _ObjectiveReducer(Iterable<AchievementObjective> objectives)
    : _objectives = objectives.map(_ObjectiveAccumulator.create).toList();

  final List<_ObjectiveAccumulator> _objectives;

  void add(AchievementEvaluationEvidence evidence) {
    for (final objective in _objectives) {
      objective.add(evidence);
    }
  }

  _ObjectiveState get state =>
      _combineStates(_objectives.map((objective) => objective.state));
}

sealed class _ObjectiveAccumulator {
  const _ObjectiveAccumulator();

  factory _ObjectiveAccumulator.create(AchievementObjective objective) =>
      switch (objective) {
        CountAchievementObjective(:final eventKind, :final target) =>
          _CountAccumulator(eventKind, target),
        ThresholdAchievementObjective(
          :final eventKind,
          :final metric,
          :final minimum,
        ) =>
          _ThresholdAccumulator(eventKind, metric, minimum),
        DistinctAchievementObjective(:final eventKind, :final target) =>
          _DistinctAccumulator(eventKind, target),
        SequenceAchievementObjective(:final eventKinds) => _SequenceAccumulator(
          eventKinds,
        ),
        CompoundAchievementObjective(:final objectives) => _CompoundAccumulator(
          objectives,
        ),
        UnknownAchievementObjective() => const _UnknownAccumulator(),
      };

  void add(AchievementEvaluationEvidence evidence);

  _ObjectiveState get state;
}

final class _CountAccumulator extends _ObjectiveAccumulator {
  _CountAccumulator(this.eventKind, this.target);

  final AchievementEventKind eventKind;
  final int target;
  var _count = 0;

  @override
  void add(AchievementEvaluationEvidence evidence) {
    if (_eventKindFor(evidence.event) == eventKind) _count++;
  }

  @override
  _ObjectiveState get state => _countState(_count, target);
}

final class _ThresholdAccumulator extends _ObjectiveAccumulator {
  _ThresholdAccumulator(this.eventKind, this.metric, this.minimum);

  final AchievementEventKind eventKind;
  final AchievementMetric metric;
  final num minimum;
  num? _maximum;
  var _missingMetric = false;

  @override
  void add(AchievementEvaluationEvidence evidence) {
    if (_eventKindFor(evidence.event) != eventKind) return;
    final value = evidence.valueFor(metric);
    if (value == null) {
      _missingMetric = true;
    } else if (_maximum == null || value > _maximum!) {
      _maximum = value;
    }
  }

  @override
  _ObjectiveState get state {
    if (_missingMetric) {
      return const _ObjectiveState(
        value: 0,
        diagnostic: AchievementEvaluationDiagnosticCode.missingMetric,
      );
    }
    if (_maximum == null) return const _ObjectiveState(value: 0);
    if (minimum == 0) return const _ObjectiveState(value: 1);
    return _ObjectiveState(value: (_maximum! / minimum).clamp(0, 1).toDouble());
  }
}

final class _DistinctAccumulator extends _ObjectiveAccumulator {
  _DistinctAccumulator(this.eventKind, this.target);

  final AchievementEventKind eventKind;
  final int target;
  final Set<Object> _values = <Object>{};

  @override
  void add(AchievementEvaluationEvidence evidence) {
    if (_eventKindFor(evidence.event) == eventKind) {
      _values.add(evidence.event.source);
    }
  }

  @override
  _ObjectiveState get state => _countState(_values.length, target);
}

final class _SequenceAccumulator extends _ObjectiveAccumulator {
  _SequenceAccumulator(this.sequence);

  final List<AchievementEventKind> sequence;
  var _matched = 0;

  @override
  void add(AchievementEvaluationEvidence evidence) {
    if (_matched < sequence.length &&
        _eventKindFor(evidence.event) == sequence[_matched]) {
      _matched++;
    }
  }

  @override
  _ObjectiveState get state => _countState(_matched, sequence.length);
}

final class _CompoundAccumulator extends _ObjectiveAccumulator {
  _CompoundAccumulator(Iterable<AchievementObjective> objectives)
    : _children = objectives.map(_ObjectiveAccumulator.create).toList();

  final List<_ObjectiveAccumulator> _children;

  @override
  void add(AchievementEvaluationEvidence evidence) {
    for (final child in _children) {
      child.add(evidence);
    }
  }

  @override
  _ObjectiveState get state =>
      _combineStates(_children.map((child) => child.state));
}

final class _UnknownAccumulator extends _ObjectiveAccumulator {
  const _UnknownAccumulator();

  @override
  void add(AchievementEvaluationEvidence evidence) {}

  @override
  _ObjectiveState get state => const _ObjectiveState(
    value: 0,
    diagnostic: AchievementEvaluationDiagnosticCode.unknownObjective,
  );
}

_ObjectiveState _combineStates(Iterable<_ObjectiveState> states) {
  var value = 1.0;
  for (final state in states) {
    if (state.diagnostic != null) return state;
    if (state.value < value) value = state.value;
  }
  return _ObjectiveState(value: value);
}

final class _ObjectiveState {
  const _ObjectiveState({required this.value, this.diagnostic});

  final double value;
  final AchievementEvaluationDiagnosticCode? diagnostic;
}
