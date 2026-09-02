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
/// `query` call them from pure, non-async code). The underlying
/// [KeyValueStore] writes are asynchronous, so every write here is
/// deliberately fire-and-forget: the in-memory cache — hydrated from, and
/// kept in lock-step with, the durable manifest and record keys — is the
/// synchronous source of truth within one process, and the manifest makes
/// that state durable across a fresh instance (ADR 0482 / D3).
final class LocalPracticeEvidenceRepository
    implements PracticeEvidenceRepository {
  LocalPracticeEvidenceRepository({required this.keyValueStore}) {
    _loadManifest();
  }

  final KeyValueStore keyValueStore;

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
  /// [deleteForPlan] / [deleteForOutcomes], never a wildcard match.
  final Map<String, PlanId> _ownership = <String, PlanId>{};

  @override
  void save(SkillEvidence evidence, {PlanId? sourcePlanId}) {
    final outcomeId = evidence.sourceOutcomeId.value;
    final envelope = <String, Object?>{
      'evidence': _encodeEvidence(evidence),
      'sourcePlanId': sourcePlanId?.value,
    };
    unawaited(
      keyValueStore.writeString(_recordKey(outcomeId), jsonEncode(envelope)),
    );
    if (!_outcomeIds.contains(outcomeId)) {
      _outcomeIds.add(outcomeId);
      _persistManifest();
    }
    _records[outcomeId] = evidence;
    if (sourcePlanId != null) {
      _ownership[outcomeId] = sourcePlanId;
    } else {
      // Explicitly clear any previous ownership so a re-save without a
      // `sourcePlanId` does not silently inherit an old relation (mirrors
      // the test-fake's F2 fix).
      _ownership.remove(outcomeId);
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
      if (_ownership[outcomeId] == planId) {
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
      if (_ownership[outcomeId] == planId && _records.containsKey(outcomeId)) {
        _removeRecord(outcomeId);
        removed++;
      }
    }
    return removed;
  }

  void _removeRecord(String outcomeId) {
    _records.remove(outcomeId);
    _ownership.remove(outcomeId);
    unawaited(keyValueStore.remove(_recordKey(outcomeId)));
    if (_outcomeIds.remove(outcomeId)) {
      _persistManifest();
    }
  }

  void _persistManifest() {
    unawaited(keyValueStore.writeString(manifestKey, jsonEncode(_outcomeIds)));
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
  /// still finds and removes the orphaned key.
  void _hydrateRecord(String outcomeId) {
    _outcomeIds.add(outcomeId);
    final raw = keyValueStore.readString(_recordKey(outcomeId));
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final evidenceJson = decoded['evidence'];
      if (evidenceJson is! Map<String, dynamic>) return;
      _records[outcomeId] = _decodeEvidence(evidenceJson);
      final ownerJson = decoded['sourcePlanId'];
      if (ownerJson is String) {
        _ownership[outcomeId] = PlanId(ownerJson);
      }
    } on Object {
      // Corrupt record: skip it, keep the sibling records readable.
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
              sampleCount: performanceJson['sampleCount'] as int? ?? 1,
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
