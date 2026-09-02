/// Persistent [PracticeEvidenceRepository] implementation (E15-R14, ADR
/// 0482 / D2, D3).
library;

import 'dart:async';
import 'dart:convert';

import '../../../../core/storage/key_value_store.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/skill_evidence.dart';
import '../../domain/repository/practice_evidence_repository.dart';

/// The first PERSISTENT [PracticeEvidenceRepository] implementation.
///
/// The never-forgets in-memory test-fake declared alongside the interface
/// is safe for tests and the mock-mode path only: bound behind the real
/// [DeletePracticePlanningData] use case it would make the
/// `PlanPrivacyScreen` delete button a silent no-op the moment the
/// provider (or the app) is rebuilt (ADR 0482 / D2, CLAUDE.md "silent
/// no-op" trap). This class is the real one.
///
/// Own key namespace ([_namespace]), never [`ss.practice_generator.plan.*`]
/// or `GenerationDraftRepository.draftStorageKey` (ADR 0482 / D3) — a bad
/// evidence write structurally cannot clobber the active plan or the
/// wizard draft.
///
/// [KeyValueStore] exposes no key enumeration, so — exactly like
/// `LocalPracticePlanRepository` — this repository persists a **manifest**
/// (the list of every `sourceOutcomeId` it has ever written) and hydrates
/// its in-memory cache from it on construction. Without the manifest,
/// [deleteForPlan] on a freshly constructed instance would not know which
/// keys to remove, and the delete would be a no-op precisely for the
/// restart case the privacy screen depends on.
///
/// [PracticeEvidenceRepository]'s methods are synchronous (mirroring the
/// test-fake's shape, since the skill-estimate reducer and the bounded
/// `query` call them from pure, non-async code, and so a fresh instance
/// opened on the same store immediately after a write/delete observes it
/// without an artificial `await` gap). The underlying [KeyValueStore]
/// writes are asynchronous, so every write here is fire-and-forget from
/// the caller's point of view — but NEVER silently so (E15-R14 fix1 / B1,
/// CLAUDE.md "silent no-op" trap):
///
///   * The physical write/remove and the matching manifest update are
///     started together (never gated behind a `.then()` on each other —
///     that would introduce a microtask gap the synchronous contract
///     above cannot afford). If either one fails, `_reconcileSave` /
///     `_reconcileRemove` asynchronously **compensates**: a failed
///     physical remove gets its id put BACK into the manifest (so the
///     still-present record stays discoverable for a future retry,
///     instead of becoming a permanent orphan); a failed physical write
///     gets its optimistically-added id taken back OUT of the manifest
///     (so a fresh instance never advertises a record that was never
///     actually persisted).
///   * The manifest write itself is **read-modify-write**: every
///     `_persistManifestAdd`/`_persistManifestRemove` call re-reads the
///     on-disk manifest immediately before writing it back, so a stale
///     instance's write can never blindly overwrite a concurrent
///     instance's delete (or vice versa).
///   * Any failure that does occur is captured in [lastWriteFailure]
///     rather than escaping as an unhandled async error; [flush] lets a
///     caller await every write/remove — and its reconciliation — before
///     inspecting the store or [lastWriteFailure].
final class LocalPracticeEvidenceRepository
    implements PracticeEvidenceRepository {
  LocalPracticeEvidenceRepository({
    required this.keyValueStore,
    this.outcomePlanLookup,
  }) {
    _loadManifest();
  }

  final KeyValueStore keyValueStore;

  /// Optional fallback ownership lookup for records saved without a
  /// `sourcePlanId`, mirroring `InMemoryPracticeEvidenceRepository`'s
  /// constructor parameter and the interface's own doc-contract
  /// (`domain/repository/practice_evidence_repository.dart:20-23`,
  /// MINOR-6 parity fix). `null` (the default) means "no fallback": a
  /// record with no recorded ownership stays immune to [deleteForPlan] /
  /// [deleteForOutcomes] — absence of ownership data is a refusal, never
  /// a wildcard.
  final PlanId? Function(String sourceOutcomeId)? outcomePlanLookup;

  /// Dedicated namespace — deliberately distinct from
  /// `ss.practice_generator.plan.*` (`LocalPracticePlanRepository`) and
  /// `ss.practice_generator.generation_draft`
  /// (`GenerationDraftRepository.draftStorageKey`), so a bad evidence
  /// write can never collide with either (ADR 0482 / D3).
  static const String _namespace = 'ss.practice_generator.evidence';

  /// Durable manifest key: a JSON array of every `sourceOutcomeId` this
  /// repository has ever written. Named after, and following, the same
  /// pattern as `LocalPracticePlanRepository.manifestKey`.
  static const String manifestKey = '$_namespace.manifest';

  static String _recordKey(String outcomeId) => '$_namespace.record.$outcomeId';

  /// Hydrated cache: every outcome id this repository currently owns, in
  /// the order it was first written. Mirrors the durable manifest.
  final List<String> _outcomeIds = <String>[];
  final Map<String, SkillEvidence> _records = <String, SkillEvidence>{};

  /// Per-record ownership data relation (ADR 0260 §5 "ownership as data").
  /// Absence here means "ownership unknown" — a refusal for
  /// [deleteForPlan] / [deleteForOutcomes], never a wildcard match (the
  /// [outcomePlanLookup] fallback is consulted first, see
  /// [_resolveOwnership]).
  final Map<String, PlanId> _ownership = <String, PlanId>{};

  /// Every write/remove currently in flight against [keyValueStore],
  /// tracked so [flush] can await them and so a failure lands in
  /// [lastWriteFailure] instead of escaping unhandled (B1 fix).
  final List<Future<void>> _pendingWrites = <Future<void>>[];

  Object? _lastWriteFailure;
  StackTrace? _lastWriteFailureStackTrace;

  /// The most recent write/remove failure surfaced by the underlying
  /// [KeyValueStore], if any. `null` once every write since construction
  /// has completed without error. Every write in this class is
  /// fire-and-forget (the interface above is synchronous), so a
  /// platform-level [StorageException] can never simply vanish: it lands
  /// here instead of escaping as an unhandled async error (E15-R14 fix1 /
  /// B1, CLAUDE.md "silent no-op" trap).
  Object? get lastWriteFailure => _lastWriteFailure;

  /// The stack trace paired with [lastWriteFailure], if any.
  StackTrace? get lastWriteFailureStackTrace => _lastWriteFailureStackTrace;

  /// Awaits every write/remove currently in flight. Primarily for tests
  /// that need a deterministic point after which [lastWriteFailure] is
  /// guaranteed to reflect any failure a fire-and-forget write produced.
  Future<void> flush() async {
    final pending = List<Future<void>>.of(_pendingWrites);
    _pendingWrites.clear();
    await Future.wait(pending);
  }

  void _track(Future<void> future) {
    _pendingWrites.add(
      future.catchError((Object error, StackTrace stackTrace) {
        _lastWriteFailure = error;
        _lastWriteFailureStackTrace = stackTrace;
      }),
    );
  }

  /// Effective ownership: the recorded data relation first, the
  /// [outcomePlanLookup] fallback second. `null` means ownership is
  /// unknown — a refusal, not a wildcard (mirrors
  /// `InMemoryPracticeEvidenceRepository._resolveOwnership`).
  PlanId? _resolveOwnership(String outcomeId) {
    final owner = _ownership[outcomeId];
    if (owner != null) return owner;
    final lookup = outcomePlanLookup;
    if (lookup == null) return null;
    return lookup(outcomeId);
  }

  @override
  void save(SkillEvidence evidence, {PlanId? sourcePlanId}) {
    final outcomeId = evidence.sourceOutcomeId.value;
    final envelope = <String, Object?>{
      'evidence': _encodeEvidence(evidence),
      'sourcePlanId': sourcePlanId?.value,
    };
    final isNew = !_outcomeIds.contains(outcomeId);
    if (isNew) _outcomeIds.add(outcomeId);
    _records[outcomeId] = evidence;
    if (sourcePlanId != null) {
      _ownership[outcomeId] = sourcePlanId;
    } else {
      // Explicitly clear any previous ownership so a re-save without a
      // `sourcePlanId` does not silently inherit an old relation (mirrors
      // the test-fake's F2 fix).
      _ownership.remove(outcomeId);
    }

    // Both operations START together — matching the synchronous-apparent
    // durability every other read in this class (and this round's whole
    // test suite) relies on: a fresh instance constructed right after
    // `save()` returns, with no `await`, must already see the write. See
    // `_reconcileSave` for what happens if either one actually fails.
    final write = keyValueStore.writeString(
      _recordKey(outcomeId),
      jsonEncode(envelope),
    );
    final manifestWrite = isNew ? _persistManifestAdd(outcomeId) : null;
    _track(_reconcileSave(outcomeId, write, manifestWrite));
  }

  /// See the class doc-comment. Reconciles the outcome of [write] (the
  /// physical record write) against [manifestWrite] (the manifest add,
  /// non-null only when [outcomeId] was new) once both settle — self-
  /// healing an inconsistency the two synchronous-apparent starts above
  /// could not observe in advance.
  Future<void> _reconcileSave(
    String outcomeId,
    Future<void> write,
    Future<void>? manifestWrite,
  ) async {
    Object? writeError;
    StackTrace? writeStackTrace;
    try {
      await write;
    } catch (error, stackTrace) {
      writeError = error;
      writeStackTrace = stackTrace;
    }

    var manifestOk = true;
    if (manifestWrite != null) {
      try {
        await manifestWrite;
      } on Object {
        manifestOk = false;
      }
    }

    if (writeError == null && manifestWrite != null && !manifestOk) {
      // The record write succeeded but the manifest add did not — retry
      // it (read-modify-write, so it is safe even if the manifest
      // changed again meanwhile).
      await _persistManifestAdd(outcomeId);
    } else if (writeError != null && manifestWrite != null && manifestOk) {
      // B1: the manifest already (optimistically) listed this NEW id,
      // but the physical record write failed — undo it. A fresh
      // instance must never advertise a record that was never actually
      // persisted.
      await _persistManifestRemove(outcomeId);
    }

    if (writeError != null) {
      Error.throwWithStackTrace(writeError, writeStackTrace!);
    }
  }

  @override
  SkillEvidence? findByOutcomeId(OutcomeId sourceOutcomeId) =>
      _records[sourceOutcomeId.value];

  @override
  List<SkillEvidence> allForSkill(String skillId) => _records.values
      .where((evidence) => evidence.skillId == skillId)
      .toList(growable: false);

  @override
  List<SkillEvidence> query({
    required String skillId,
    required DateTime asOf,
    DateTime? measuredFrom,
    DateTime? measuredTo,
  }) {
    final asOfUtc = asOf.toUtc();
    final fromUtc = measuredFrom?.toUtc();
    final toUtc = measuredTo?.toUtc();
    if (fromUtc != null && toUtc != null && toUtc.isBefore(fromUtc)) {
      throw ArgumentError.value(
        measuredTo,
        'measuredTo',
        'must not be before measuredFrom',
      );
    }
    return _records.values
        .where((evidence) {
          if (evidence.skillId != skillId) return false;
          if (!evidence.isValidAt(asOfUtc)) return false;
          if (fromUtc != null && evidence.measuredAt.isBefore(fromUtc)) {
            return false;
          }
          if (toUtc != null && evidence.measuredAt.isAfter(toUtc)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  @override
  int deleteForPlan(PlanId planId) {
    var removed = 0;
    for (final outcomeId in _outcomeIds.toList(growable: false)) {
      if (_resolveOwnership(outcomeId) == planId) {
        _removeRecord(outcomeId);
        removed++;
      }
    }
    return removed;
  }

  @override
  int deleteForOutcomes(PlanId planId, Set<OutcomeId> sourceOutcomeIds) {
    var removed = 0;
    for (final id in sourceOutcomeIds) {
      final outcomeId = id.value;
      if (_resolveOwnership(outcomeId) == planId &&
          _records.containsKey(outcomeId)) {
        _removeRecord(outcomeId);
        removed++;
      }
    }
    return removed;
  }

  /// B1 fix: removes the in-process view immediately (the synchronous
  /// contract's "current instance" behaviour), then starts the physical
  /// removal and the matching manifest update TOGETHER (see the class
  /// doc-comment for why they cannot be `.then()`-chained). If the
  /// physical [KeyValueStore.remove] call fails, `_reconcileRemove` puts
  /// the id back into the manifest — it stays discoverable on disk (by
  /// this or a future instance) instead of becoming a permanently
  /// unreachable orphan the moment an unrelated later write rewrites the
  /// manifest.
  void _removeRecord(String outcomeId) {
    _records.remove(outcomeId);
    _ownership.remove(outcomeId);
    final wasTracked = _outcomeIds.remove(outcomeId);
    final remove = keyValueStore.remove(_recordKey(outcomeId));
    final manifestRemove = wasTracked
        ? _persistManifestRemove(outcomeId)
        : null;
    _track(_reconcileRemove(outcomeId, remove, manifestRemove));
  }

  /// See [_reconcileSave] (the mirror-image reconciliation for the
  /// delete path) and the class doc-comment.
  Future<void> _reconcileRemove(
    String outcomeId,
    Future<void> remove,
    Future<void>? manifestRemove,
  ) async {
    Object? removeError;
    StackTrace? removeStackTrace;
    try {
      await remove;
    } catch (error, stackTrace) {
      removeError = error;
      removeStackTrace = stackTrace;
    }

    var manifestOk = true;
    if (manifestRemove != null) {
      try {
        await manifestRemove;
      } on Object {
        manifestOk = false;
      }
    }

    if (removeError == null && manifestRemove != null && !manifestOk) {
      // The physical remove succeeded but the manifest drop did not —
      // retry it (read-modify-write, safe even if the manifest changed
      // again meanwhile).
      await _persistManifestRemove(outcomeId);
    } else if (removeError != null && manifestRemove != null && manifestOk) {
      // B1: the manifest already (optimistically) dropped this id, but
      // the physical remove failed — put it back so the still-present
      // record stays discoverable for a future retry.
      await _persistManifestAdd(outcomeId);
    }

    if (removeError != null) {
      Error.throwWithStackTrace(removeError, removeStackTrace!);
    }
  }

  /// Read-modify-write manifest add (M2 fix): re-reads the on-disk
  /// manifest immediately before writing, so a write from one instance
  /// can never blindly clobber a concurrent delete performed by another
  /// instance sharing the same store (the prior implementation always
  /// wrote this instance's full, possibly-stale `_outcomeIds` list).
  Future<void> _persistManifestAdd(String outcomeId) async {
    final ids = _readManifestIds();
    if (!ids.contains(outcomeId)) {
      ids.add(outcomeId);
      await keyValueStore.writeString(manifestKey, jsonEncode(ids));
    }
  }

  /// Read-modify-write manifest remove (M2 fix) — see [_persistManifestAdd].
  Future<void> _persistManifestRemove(String outcomeId) async {
    final ids = _readManifestIds();
    if (ids.remove(outcomeId)) {
      await keyValueStore.writeString(manifestKey, jsonEncode(ids));
    }
  }

  /// The manifest as it stands on disk right now. A missing or corrupt
  /// manifest reads as empty — the caller (add/remove) treats that as
  /// "nothing else recorded yet", never as a reason to fail the write.
  List<String> _readManifestIds() {
    final raw = keyValueStore.readString(manifestKey);
    if (raw == null) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return <String>[
        for (final entry in decoded)
          if (entry is String) entry,
      ];
    } on Object {
      return <String>[];
    }
  }

  /// F1-style fix (mirrors `LocalPracticePlanRepository._loadManifest`): a
  /// missing manifest means "nothing written yet"; a present-but-unreadable
  /// manifest is treated as empty rather than blocking construction — a
  /// later write rewrites it as a complete list.
  void _loadManifest() {
    final raw = keyValueStore.readString(manifestKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final entry in decoded) {
        if (entry is String && !_outcomeIds.contains(entry)) {
          _hydrateRecord(entry);
        }
      }
    } on Object {
      // Corrupt manifest: best-effort skipped, exactly like the plan
      // repository's manifest recovery.
    }
  }

  /// Reads and decodes one record during hydration. A corrupt or
  /// unreadable individual record is skipped (record-level fault
  /// isolation, same posture as `LocalPracticePlanRepository.readArchive`)
  /// — the outcome id stays tracked in the manifest so `deleteForPlan`
  /// still finds it.
  ///
  /// M1 fix (E15-R14 fix1): ownership is read BEFORE the `evidence` body
  /// is decoded. Ownership is an independent data relation from the
  /// evidence payload — a corrupt/unknown `evidence` field must not also
  /// leave the record un-owned, which would make it permanently immune to
  /// [deleteForPlan] / [deleteForOutcomes] (the previous `return` on a bad
  /// evidence body skipped the ownership read entirely, contradicting this
  /// very doc-comment).
  void _hydrateRecord(String outcomeId) {
    _outcomeIds.add(outcomeId);
    final raw = keyValueStore.readString(_recordKey(outcomeId));
    if (raw == null) return;
    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return;
      decoded = value;
    } on Object {
      // Corrupt envelope: nothing to read, not even ownership.
      return;
    }
    final ownerJson = decoded['sourcePlanId'];
    if (ownerJson is String) {
      _ownership[outcomeId] = PlanId(ownerJson);
    }
    try {
      final evidenceJson = decoded['evidence'];
      if (evidenceJson is! Map<String, dynamic>) return;
      _records[outcomeId] = _decodeEvidence(evidenceJson);
    } on Object {
      // Corrupt evidence body: skip caching it, but the ownership read
      // above still makes this key reachable through deleteForPlan /
      // deleteForOutcomes (record-level fault isolation).
    }
  }

  Map<String, Object?> _encodeEvidence(SkillEvidence evidence) {
    final performance = evidence.performance;
    final discomfort = evidence.discomfort;
    return <String, Object?>{
      'skillId': evidence.skillId,
      'source': evidence.source.code,
      'sourceOutcomeId': evidence.sourceOutcomeId.toJson(),
      'measurementVersion': evidence.measurementVersion,
      'measuredAt': evidence.measuredAt.toIso8601String(),
      'capturedAt': evidence.capturedAt.toIso8601String(),
      'confidence': evidence.confidence,
      'validUntil': evidence.validUntil?.toIso8601String(),
      if (performance != null)
        'performance': <String, Object?>{
          'metricCode': performance.metricCode,
          'value': performance.value,
          'sampleCount': performance.sampleCount,
        },
      if (discomfort != null)
        'discomfort': <String, Object?>{'category': discomfort.category.code},
    };
  }

  SkillEvidence _decodeEvidence(Map<String, dynamic> json) {
    final performanceJson = json['performance'];
    final discomfortJson = json['discomfort'];
    return SkillEvidence(
      skillId: json['skillId'] as String,
      source: EvidenceSource.fromCode(json['source'] as String?),
      sourceOutcomeId: OutcomeId.fromJson(json['sourceOutcomeId']),
      measurementVersion: json['measurementVersion'] as int,
      measuredAt: DateTime.parse(json['measuredAt'] as String),
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      confidence: (json['confidence'] as num).toDouble(),
      validUntil: json['validUntil'] == null
          ? null
          : DateTime.parse(json['validUntil'] as String),
      performance: performanceJson == null
          ? null
          : PerformanceEvidence(
              metricCode:
                  (performanceJson as Map<String, dynamic>)['metricCode']
                      as String,
              value: (performanceJson['value'] as num).toDouble(),
              // MINOR-2 fix: required, never a silent fallback to 1 — every
              // record this class itself ever writes always includes it
              // (`_encodeEvidence` above), so a missing value means the
              // record is corrupt and belongs on the "skip it" path, not
              // silently misrepresenting the sample size as 1.
              sampleCount: performanceJson['sampleCount'] as int,
            ),
      discomfort: discomfortJson == null
          ? null
          : DiscomfortReport(
              category: DiscomfortCategory.fromCode(
                (discomfortJson as Map<String, dynamic>)['category'] as String?,
              ),
            ),
    );
  }
}
