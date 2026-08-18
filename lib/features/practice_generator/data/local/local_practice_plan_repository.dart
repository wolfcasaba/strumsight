/// Local, offline-first persistence for active practice plans, drafts, and
/// archived revisions/outcomes (ADR 0267).
///
/// Three key namespaces, isolated by construction (ADR 0259 §3 extended):
///
/// * **drafts** — `ss.practice_generator.plan.draft.<draftKey>`: in-progress
///   plans assembled by the wizard, never touching an active record.
/// * **active** — `ss.practice_generator.plan.active.<length:planId>.
///   <length:revisionId>` for the **immutable** record under a
///   per-revision-id key, plus a single
///   `ss.practice_generator.plan.active_pointer` that names the
///   `{planId, revisionId}` pair the app loads on start. The pointer is the
///   *last* thing written on `activate`, so a partial write leaves the
///   prior pointer intact.
/// * **archive** — `ss.practice_generator.plan.archive.<length:planId>.
///   revisions.<length:id>` and `…outcomes.<length:id>` for the bounded
///   history, plus `…index` records that list the ids in newest-first order.
///
/// Why per-revision-id storage instead of a single document:
/// * A **single-record corruption** stays single-record. A serialised
///   plan blob truncated by an interrupted write lives at
///   `…active.<revisionId>` until the next pointer switch, and the active
///   plan survives from the prior revision's record. Per ADR 0267 §5.2,
///   "ONE corrupt record NEM viszi el a többit" is non-negotiable.
/// * The atomicity invariant (§5.3) reduces to **key order**: write the
///   new immutable record first, then move the pointer. A crash between
///   the two keeps the prior active pointer visible — there is no
///   half-written active record, only an orphan keyed by the new revision
///   id.
/// * `activate(plan)` repeated with the same `{planId, revisionId}` is
///   structurally idempotent: the pointer write would not move.
///
/// This class owns no domain authenticator and accepts no network identity
/// (E07-R18 NOTE-4 follow-up). The composition root is responsible for
/// handing a per-profile store to it.
library;

import 'dart:async';
import 'dart:convert';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../application/service/generation_orchestrator.dart'
    show GenerationPlanActivation;
import '../../domain/id/planner_ids.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/practice_block.dart';
import 'practice_plan_migrator.dart';
import 'practice_plan_serializer.dart';

/// Public view over the persisted practice log: the revisions and outcomes
/// whose keys are still alive on disk.
final class ArchivedPracticeLog {
  const ArchivedPracticeLog({
    required this.revisions,
    required this.outcomes,
    required this.droppedRevisions,
    required this.droppedOutcomes,
  });

  /// Newest-first ordered [ArchivedRevision]s.
  final List<ArchivedRevision> revisions;

  /// Newest-first ordered [PracticeOutcome]s.
  final List<PracticeOutcome> outcomes;

  /// Count of revisions evicted by the bounded-history policy on this read.
  final int droppedRevisions;

  /// Count of outcomes evicted by the bounded-history policy on this read.
  final int droppedOutcomes;

  bool get isEmpty => revisions.isEmpty && outcomes.isEmpty;
}

/// The result of an `activate` call: the new active pointer if a switch
/// happened, or the unchanged pointer if the call was structurally
/// idempotent.
final class ActivePlanActivationOutcome {
  const ActivePlanActivationOutcome({
    required this.pointer,
    required this.revisionWritten,
  });

  /// The pointer after the call. `==` to the prior pointer when
  /// [revisionWritten] is false.
  final ActivePlanPointer pointer;

  /// True when a new immutable record and a new pointer were written.
  /// False when activate was a structural no-op (same `{planId,
  /// revisionId}` pair already active).
  final bool revisionWritten;
}

/// A present active-pointer record cannot be decoded safely. This is distinct
/// from an absent pointer (first launch), so callers never mistake corruption
/// for an empty store.
final class PracticePlanActivePointerCorruptionException implements Exception {
  const PracticePlanActivePointerCorruptionException({
    required this.key,
    required this.cause,
    required this.stackTrace,
  });

  final String key;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() =>
      'PracticePlanActivePointerCorruptionException(key: $key)';
}

/// An archive index is present but cannot be decoded safely. Appending is
/// refused so a corrupt index is never replaced with a fresh empty one.
final class PracticePlanArchiveIndexCorruptionException implements Exception {
  const PracticePlanArchiveIndexCorruptionException({
    required this.key,
    required this.cause,
    required this.stackTrace,
  });

  final String key;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'PracticePlanArchiveIndexCorruptionException(key: $key)';
}

/// Local repository implementation that satisfies the
/// [GenerationPlanActivation] contract for the orchestrator AND owns the
/// archived revisions and outcomes (the store layer that future history
/// views will read).
///
/// Every public method returns [AppResult] — exceptions are a programming
/// error; failures travel as values (SDD Ch2 §7.1).
class LocalPracticePlanRepository implements GenerationPlanActivation {
  LocalPracticePlanRepository({
    required this.keyValueStore,
    required this.resolveCandidate,
    PracticePlanSerializer? serializer,
    PracticePlanHistoryPolicy? historyPolicy,
  }) : serializer = serializer ?? const PracticePlanSerializer(),
       historyPolicy = historyPolicy ?? const PracticePlanHistoryPolicy();

  final KeyValueStore keyValueStore;
  final ExerciseCandidateResolver resolveCandidate;
  final PracticePlanSerializer serializer;
  final PracticePlanHistoryPolicy historyPolicy;

  // ---------------------------------------------------------------------
  // Key namespace (A5: draft and active share NO key prefix)
  // ---------------------------------------------------------------------

  static const String _namespace = 'ss.practice_generator.plan';

  /// Single, namespaced pointer to the active `{planId, revisionId}` pair.
  static const String activePointerKey = '$_namespace.active_pointer';

  /// `draft.<draftKey>` — the only place a draft ever lives.
  static String draftStorageKey(String draftKey) =>
      '$_namespace.draft.$draftKey';

  /// `active.<length:planId>.<length:revisionId>` — the *immutable* record
  /// under a per-revision-id key. Length-prefixed segments keep dotted ids
  /// injective: `{a.b, c}` cannot collide with `{a, b.c}`.
  static String activePlanRevisionKey({
    required PlanId planId,
    required RevisionId revisionId,
  }) =>
      '$_namespace.active.${_keySegment(planId.value)}.'
      '${_keySegment(revisionId.value)}';

  /// `archive.<length:planId>.revisions.index` — newest-first list of
  /// `RevisionId` values for that plan.
  static String archiveRevisionsIndexKey(PlanId planId) =>
      '$_namespace.archive.${_keySegment(planId.value)}.revisions.index';

  /// `archive.<length:planId>.revisions.<length:revisionId>` — one immutable
  /// stored revision snapshot.
  static String archiveRevisionKey({
    required PlanId planId,
    required RevisionId revisionId,
  }) =>
      '$_namespace.archive.${_keySegment(planId.value)}.revisions.'
      '${_keySegment(revisionId.value)}';

  /// `archive.<length:planId>.outcomes.index` — newest-first list of
  /// `OutcomeId` values for that plan.
  static String archiveOutcomesIndexKey(PlanId planId) =>
      '$_namespace.archive.${_keySegment(planId.value)}.outcomes.index';

  /// `archive.<length:planId>.outcomes.<length:outcomeId>` — one immutable
  /// stored outcome record.
  static String archiveOutcomeKey({
    required PlanId planId,
    required OutcomeId outcomeId,
  }) =>
      '$_namespace.archive.${_keySegment(planId.value)}.outcomes.'
      '${_keySegment(outcomeId.value)}';

  /// Stable, injective segment encoding for persistence-key identifiers.
  /// The length is the Dart string's UTF-16 code-unit count, which is the
  /// same representation used by the key-value store API.
  static String _keySegment(String value) => '${value.length}:$value';

  // ---------------------------------------------------------------------
  // Activation (the GenerationPlanActivation contract)
  // ---------------------------------------------------------------------

  /// [GenerationPlanActivation.activate] — persists [plan] as the
  /// currently-active plan. A platform-level write failure aborts the
  /// future with the original `StorageException` (re-thrown). The
  /// orchestrator surfaces that as a [Failure]. The idempotence and
  /// pointer-stability invariants are observable through
  /// [activateAndReport].
  @override
  Future<void> activate(AdaptivePracticePlan plan) async {
    final result = await activateAndReport(plan);
    if (result.isFailure) {
      final error = result.failureOrNull!;
      if (error.cause is Exception) throw error.cause as Exception;
      if (error.cause is Error) throw error.cause as Error;
      throw StateError('activation failed: ${error.code}');
    }
  }

  /// Internal-facing variant of [activate] that returns the rich outcome
  /// (pointer, whether a record was actually written) for callers and
  /// tests that need to observe the activation contract.
  Future<AppResult<ActivePlanActivationOutcome>> activateAndReport(
    AdaptivePracticePlan plan,
  ) async => _runWrite(() async {
    final priorPointer = _readActivePointerSync();
    final pointer = ActivePlanPointer(
      planId: plan.id,
      revisionId: plan.activeRevisionId,
    );
    final revisionKey = activePlanRevisionKey(
      planId: plan.id,
      revisionId: plan.activeRevisionId,
    );

    if (priorPointer == pointer) {
      // Idempotent path: same {planId, revisionId} already active. No
      // record write, no pointer write — return the unchanged pointer.
      return Success<ActivePlanActivationOutcome>(
        ActivePlanActivationOutcome(pointer: pointer, revisionWritten: false),
      );
    }

    // Step 1: write the immutable record under its revision-id key.
    final recordEnvelope = serializer.encodePlanRecord(plan);
    await keyValueStore.writeString(revisionKey, jsonEncode(recordEnvelope));

    // Step 2: switch the pointer last.
    final pointerEnvelope = serializer.encodeActivePointer(pointer);
    await keyValueStore.writeString(
      activePointerKey,
      jsonEncode(pointerEnvelope),
    );

    // Step 3 (best-effort housekeeping): if there was a previous active
    // pointer on a different revision id, drop the previous record only
    // AFTER the new pointer is in place. The previous record stays
    // observable through the archive index anyway.
    if (priorPointer != null &&
        (priorPointer.planId != pointer.planId ||
            priorPointer.revisionId != pointer.revisionId)) {
      final priorRecordKey = activePlanRevisionKey(
        planId: priorPointer.planId,
        revisionId: priorPointer.revisionId,
      );
      try {
        await keyValueStore.remove(priorRecordKey);
      } on StorageException {
        // The pointer is already committed. Retaining a harmless orphaned
        // old record is safer than reporting the completed activation as a
        // failure; a later successful activation may remove it.
        return Success<ActivePlanActivationOutcome>(
          ActivePlanActivationOutcome(pointer: pointer, revisionWritten: true),
        );
      }
    }

    return Success<ActivePlanActivationOutcome>(
      ActivePlanActivationOutcome(pointer: pointer, revisionWritten: true),
    );
  });

  // ---------------------------------------------------------------------
  // Active plan read
  // ---------------------------------------------------------------------

  /// Loads the currently-active plan, or `Success(null)` when none has been
  /// activated. A present-but-corrupt pointer is a controlled failure, never
  /// silently reclassified as first launch.
  Future<AppResult<AdaptivePracticePlan?>> readActivePlan() async =>
      _runRead(() async {
        final pointer = _readActivePointerSync();
        if (pointer == null) return const Success<AdaptivePracticePlan?>(null);
        final key = activePlanRevisionKey(
          planId: pointer.planId,
          revisionId: pointer.revisionId,
        );
        final raw = keyValueStore.readString(key);
        if (raw == null) return const Success<AdaptivePracticePlan?>(null);
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) {
            // A present-but-non-object envelope (list, null, number, …) is
            // persistence corruption, NOT an absent record. The serializer
            // has a stable code for this shape; the cause we surface carries
            // no persisted bytes (the brief §10/S-01 forbids leaking the raw
            // value into a StorageFailure).
            throw PracticePlanSerializerException(
              PracticePlanSerializerErrorCode.notAnObject,
            );
          }
          final plan = serializer.decodePlanRecord(
            decoded,
            resolveCandidate: resolveCandidate,
          );
          return Success<AdaptivePracticePlan?>(plan);
        } on PracticePlanSerializerException catch (e, stackTrace) {
          return Failure<AdaptivePracticePlan?>(
            StorageFailure(
              code: FailureCode.storageRead,
              cause: e,
              stackTrace: stackTrace,
            ),
          );
        }
      });

  // ---------------------------------------------------------------------
  // Drafts (A5: separate from active)
  // ---------------------------------------------------------------------

  Future<AppResult<void>> saveDraft({
    required String draftKey,
    required AdaptivePracticePlan plan,
  }) async => _runWrite(() async {
    final envelope = serializer.encodeDraft(
      PracticePlanDraftEnvelope(
        draftKey: draftKey,
        plan: plan,
        savedAt: DateTime.now().toUtc(),
      ),
    );
    await keyValueStore.writeString(
      draftStorageKey(draftKey),
      jsonEncode(envelope),
    );
    return const Success<void>(null);
  });

  Future<AppResult<AdaptivePracticePlan?>> readDraft(String draftKey) async =>
      _runRead(() async {
        final raw = keyValueStore.readString(draftStorageKey(draftKey));
        if (raw == null) return const Success<AdaptivePracticePlan?>(null);
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) {
            // A present-but-non-object envelope (list, null, number, …) is
            // persistence corruption, NOT an absent draft (S-01). The cause
            // we surface carries no persisted bytes.
            throw PracticePlanSerializerException(
              PracticePlanSerializerErrorCode.notAnObject,
            );
          }
          final draft = serializer.decodeDraft(
            decoded,
            resolveCandidate: resolveCandidate,
          );
          return Success<AdaptivePracticePlan?>(draft.plan);
        } on PracticePlanSerializerException catch (e, stackTrace) {
          return Failure<AdaptivePracticePlan?>(
            StorageFailure(
              code: FailureCode.storageRead,
              cause: e,
              stackTrace: stackTrace,
            ),
          );
        }
      });

  Future<AppResult<void>> clearDraft(String draftKey) async =>
      _runWrite(() async {
        await keyValueStore.remove(draftStorageKey(draftKey));
        return const Success<void>(null);
      });

  // ---------------------------------------------------------------------
  // Archive: revisions + outcomes (A6 bounded, A4 idempotent)
  // ---------------------------------------------------------------------

  /// Appends [revision] to the bounded archive for its plan. Idempotent on
  /// `revision.id`: a second call with the same id is a no-op.
  ///
  /// Once the index would exceed [PracticePlanHistoryPolicy.maxRevisionsPerPlan],
  /// the oldest entries (and their record keys) are evicted. Eviction is
  /// atomic per eviction: the index is rewritten first, then the dropped
  /// record is removed. A crash between the two leaves a stale index entry
  /// pointing at a now-removed record — `readArchive` recognises that and
  /// silently skips the missing key.
  Future<AppResult<void>> appendRevision(ArchivedRevision revision) async =>
      _runWrite(() async {
        final indexKey = archiveRevisionsIndexKey(revision.planId);
        final existing = _readIdList<RevisionId>(
          indexKey,
          decode: RevisionId.fromJson,
        );
        final existingSet = existing.toSet();
        if (existingSet.contains(revision.id)) {
          return const Success<void>(null);
        }
        final recordKey = archiveRevisionKey(
          planId: revision.planId,
          revisionId: revision.id,
        );
        final envelope = serializer.encodeRevisionRecord(revision);
        await keyValueStore.writeString(recordKey, jsonEncode(envelope));

        final updated = <RevisionId>[revision.id, ...existing];
        final capped = historyPolicy.capRevisions(updated);

        await keyValueStore.writeString(
          indexKey,
          jsonEncode(serializer.encodeArchivedRevisionsIndex(capped)),
        );

        // Eviction: dropped ids lose their record key. The index itself is
        // already shrunk above, so the next read path will not look them
        // up.
        final kept = capped.toSet();
        for (final id in existing) {
          if (!kept.contains(id)) {
            await keyValueStore.remove(
              archiveRevisionKey(planId: revision.planId, revisionId: id),
            );
          }
        }
        return const Success<void>(null);
      });

  /// Appends [outcome] to the bounded outcome log. Idempotent on
  /// `outcome.id` (A4).
  Future<AppResult<void>> appendOutcome(PracticeOutcome outcome) async =>
      _runWrite(() async {
        final indexKey = archiveOutcomesIndexKey(outcome.planId);
        final existing = _readIdList<OutcomeId>(
          indexKey,
          decode: OutcomeId.fromJson,
        );
        final existingSet = existing.toSet();
        if (existingSet.contains(outcome.id)) {
          return const Success<void>(null);
        }
        final recordKey = archiveOutcomeKey(
          planId: outcome.planId,
          outcomeId: outcome.id,
        );
        final envelope = serializer.encodeOutcomeRecord(outcome);
        await keyValueStore.writeString(recordKey, jsonEncode(envelope));

        final updated = <OutcomeId>[outcome.id, ...existing];
        final capped = historyPolicy.capOutcomes(updated);

        await keyValueStore.writeString(
          indexKey,
          jsonEncode(serializer.encodeArchivedOutcomesIndex(capped)),
        );

        final kept = capped.toSet();
        for (final id in existing) {
          if (!kept.contains(id)) {
            await keyValueStore.remove(
              archiveOutcomeKey(planId: outcome.planId, outcomeId: id),
            );
          }
        }
        return const Success<void>(null);
      });

  /// Loads the archived revisions and outcomes for [planId]. Corrupt or
  /// removed individual records are silently dropped — record-level fault
  /// isolation per ADR 0267 §5.2.
  Future<AppResult<ArchivedPracticeLog>> readArchive(PlanId planId) async =>
      _runRead(() async {
        final dropped = _ReadDropCounts();
        final revisions = await _readRevisions(planId, dropped);
        final outcomes = await _readOutcomes(planId, dropped);
        return Success<ArchivedPracticeLog>(
          ArchivedPracticeLog(
            revisions: revisions,
            outcomes: outcomes,
            droppedRevisions: dropped.revisions,
            droppedOutcomes: dropped.outcomes,
          ),
        );
      });

  Future<List<ArchivedRevision>> _readRevisions(
    PlanId planId,
    _ReadDropCounts dropped,
  ) async {
    final indexKey = archiveRevisionsIndexKey(planId);
    final indexIds = _readIdList<RevisionId>(
      indexKey,
      decode: RevisionId.fromJson,
    );
    final out = <ArchivedRevision>[];
    for (final id in indexIds) {
      final raw = keyValueStore.readString(
        archiveRevisionKey(planId: planId, revisionId: id),
      );
      if (raw == null) {
        dropped.revisions++;
        continue;
      }
      Map<String, dynamic> decoded;
      try {
        final v = jsonDecode(raw);
        if (v is! Map<String, dynamic>) {
          dropped.revisions++;
          continue;
        }
        decoded = v;
      } catch (_) {
        dropped.revisions++;
        continue;
      }
      try {
        out.add(
          serializer.decodeRevisionRecord(
            decoded,
            resolveCandidate: resolveCandidate,
          ),
        );
      } on PracticePlanSerializerException {
        dropped.revisions++;
      } on PracticePlanMigratorException {
        // A too-new revision cannot be decoded on this build;
        // record-level isolation (A2): drop the one and keep the rest.
        dropped.revisions++;
      } catch (_) {
        // Any other decode-time exception (FormatException from
        // DateTime.parse, ArgumentError from a typed id decoder,
        // TypeError from a missing field, …) is still record-level
        // corruption. The healthy sibling must remain readable —
        // never let one bad body take the whole archive with it
        // (S-02). The original exception is intentionally swallowed:
        // the dropped* counter is the only signal the caller gets.
        dropped.revisions++;
      }
    }
    return out;
  }

  Future<List<PracticeOutcome>> _readOutcomes(
    PlanId planId,
    _ReadDropCounts dropped,
  ) async {
    final indexKey = archiveOutcomesIndexKey(planId);
    final indexIds = _readIdList<OutcomeId>(
      indexKey,
      decode: OutcomeId.fromJson,
    );
    final out = <PracticeOutcome>[];
    for (final id in indexIds) {
      final raw = keyValueStore.readString(
        archiveOutcomeKey(planId: planId, outcomeId: id),
      );
      if (raw == null) {
        dropped.outcomes++;
        continue;
      }
      Map<String, dynamic> decoded;
      try {
        final v = jsonDecode(raw);
        if (v is! Map<String, dynamic>) {
          dropped.outcomes++;
          continue;
        }
        decoded = v;
      } catch (_) {
        dropped.outcomes++;
        continue;
      }
      try {
        out.add(serializer.decodeOutcomeRecord(decoded));
      } on PracticePlanSerializerException {
        dropped.outcomes++;
      } on PracticePlanMigratorException {
        // A too-new outcome cannot be decoded on this build;
        // record-level isolation (A2): drop the one and keep the rest.
        dropped.outcomes++;
      } catch (_) {
        // Any other decode-time exception (FormatException from
        // DateTime.parse, ArgumentError from a typed id decoder,
        // TypeError from a missing field, …) is still record-level
        // corruption. Sibling records remain readable (S-02). The
        // original exception is intentionally swallowed; the
        // dropped* counter is the only signal the caller gets.
        dropped.outcomes++;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------

  ActivePlanPointer? _readActivePointerSync() {
    final raw = keyValueStore.readString(activePointerKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('active pointer must be a JSON object');
      }
      return serializer.decodeActivePointer(decoded);
    } catch (error, stackTrace) {
      throw PracticePlanActivePointerCorruptionException(
        key: activePointerKey,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  List<T> _readIdList<T>(String key, {required T Function(Object?) decode}) {
    final raw = keyValueStore.readString(key);
    if (raw == null) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('archive index must be a JSON object');
      }
      if (decoded['kind'] == PracticePlanRecordKind.archivedRevisionIndex) {
        return serializer.decodeArchivedRevisionsIndex(decoded).cast<T>();
      }
      if (decoded['kind'] == PracticePlanRecordKind.archivedOutcomeIndex) {
        return serializer.decodeArchivedOutcomesIndex(decoded).cast<T>();
      }
      throw const FormatException('archive index kind is not recognized');
    } catch (error, stackTrace) {
      throw PracticePlanArchiveIndexCorruptionException(
        key: key,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<AppResult<T>> _runRead<T>(Future<AppResult<T>> Function() body) async {
    try {
      return await body();
    } on StorageException catch (e, stackTrace) {
      return Failure<T>(
        StorageFailure(
          code: FailureCode.storageRead,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    } catch (e, stackTrace) {
      return Failure<T>(
        StorageFailure(
          code: FailureCode.storageRead,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<AppResult<T>> _runWrite<T>(
    Future<AppResult<T>> Function() body,
  ) async {
    try {
      return await body();
    } on StorageException catch (e, stackTrace) {
      return Failure<T>(
        StorageFailure(
          code: FailureCode.storageWrite,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    } catch (e, stackTrace) {
      return Failure<T>(
        StorageFailure(
          code: FailureCode.storageWrite,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

/// Bounded-history policy for the archive (A6).
///
/// Revisions are bounded by [maxRevisionsPerPlan]; outcomes by
/// [maxOutcomesPerPlan]. Both caps are *documented maxima* — the
/// repository keeps the newest entries and evicts the oldest from the
/// tail of the newest-first index.
///
/// "Closed range" means: every revision that survives the cap is one that
/// has already been archived (it was either kept or written by this very
/// call). The cap never rewrites an existing revision record; it only
/// drops records no longer referenced from the index.
class PracticePlanHistoryPolicy {
  const PracticePlanHistoryPolicy({
    this.maxRevisionsPerPlan = 50,
    this.maxOutcomesPerPlan = 200,
  }) : assert(maxRevisionsPerPlan > 0),
       assert(maxOutcomesPerPlan > 0);

  final int maxRevisionsPerPlan;
  final int maxOutcomesPerPlan;

  List<RevisionId> capRevisions(List<RevisionId> ids) =>
      ids.length <= maxRevisionsPerPlan
      ? List<RevisionId>.unmodifiable(ids)
      : List<RevisionId>.unmodifiable(ids.sublist(0, maxRevisionsPerPlan));

  List<OutcomeId> capOutcomes(List<OutcomeId> ids) =>
      ids.length <= maxOutcomesPerPlan
      ? List<OutcomeId>.unmodifiable(ids)
      : List<OutcomeId>.unmodifiable(ids.sublist(0, maxOutcomesPerPlan));
}

/// Mutable helper used by [LocalPracticePlanRepository.readArchive] to
/// count how many index entries had to be dropped because their record
/// was unreadable.
class _ReadDropCounts {
  int revisions = 0;
  int outcomes = 0;
}
