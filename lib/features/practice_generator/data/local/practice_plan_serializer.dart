/// Round-trip JSON envelope for the local practice-plan repository
/// (ADR 0267).
///
/// Every record written by [LocalPracticePlanRepository] goes through one of
/// the `encode*` methods here; every read goes through one of the `decode*`
/// methods. The envelope is four fields:
///
/// ```json
/// {"schemaVersion": 1, "kind": "<record kind>", "body": {...}, "checksum": "<sha256 hex>"}
/// ```
///
/// * [PracticePlanEnvelope.schemaVersion] is the **envelope** schema — "did
///   the body shape change?", not the domain schema of the
///   [AdaptivePracticePlan] or its revisions. It is what the migrator gates
///   on.
/// * `checksum` is a SHA-256 hex of the deterministic, key-sorted JSON
///   representation of the body alone. The envelope fields never
///   contribute, so re-stamping a checksum is independent of itself.
/// * A record that decodes with a mismatched checksum is treated as
///   corruption (A8) and surfaces as [PracticePlanSerializerException] with
///   code `checksumMismatch` — never a silent re-read.
///
/// The serializer never decides whether a future [schemaVersion] is
/// readable. That responsibility belongs to [PracticePlanMigrator]. Here,
/// `decode` validates the envelope shape and the checksum; the migrator
/// decides whether the inner body is intelligible.
library;

import 'dart:convert';
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;

import '../../domain/id/planner_ids.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/plan_revision.dart';
import '../../domain/model/practice_block.dart';
import '../../domain/model/practice_goal.dart';
import '../../domain/model/weekly_availability.dart';
import 'practice_plan_migrator.dart';

/// What the envelope's `kind` field is allowed to be. Stable string codes,
/// persisted across builds.
abstract final class PracticePlanRecordKind {
  static const String plan = 'practice_plan.active_record';
  static const String revision = 'practice_plan.revision';
  static const String outcome = 'practice_plan.outcome';
  static const String archivedRevisionIndex =
      'practice_plan.archived_revisions_index';
  static const String archivedOutcomeIndex =
      'practice_plan.archived_outcomes_index';
  static const String activePointer = 'practice_plan.active_pointer';
  static const String draft = 'practice_plan.draft';
}

/// Reasons a record can be rejected. Stable, machine-readable codes.
abstract final class PracticePlanSerializerErrorCode {
  static const String notAnObject = 'practice_plan.serializer.not_an_object';
  static const String schemaVersionMissing =
      'practice_plan.serializer.schemaVersion.missing';
  static const String schemaVersionNotInt =
      'practice_plan.serializer.schemaVersion.not_int';
  static const String kindMissing = 'practice_plan.serializer.kind.missing';
  static const String kindUnknown = 'practice_plan.serializer.kind.unknown';
  static const String bodyMissing = 'practice_plan.serializer.body.missing';
  static const String checksumMissing =
      'practice_plan.serializer.checksum.missing';
  static const String checksumMalformed =
      'practice_plan.serializer.checksum.malformed';
  static const String checksumMismatch =
      'practice_plan.serializer.checksum.mismatch';
  static const String bodyInvalid = 'practice_plan.serializer.body.invalid';
}

/// One malformed/corrupt/unknown-schema payload. Always carries a stable
/// [code]; never the offending value (a record may carry user notes).
class PracticePlanSerializerException implements Exception {
  PracticePlanSerializerException(this.code, {this.field});

  final String code;
  final String? field;

  @override
  String toString() =>
      'PracticePlanSerializerException($code'
      '${field == null ? '' : ', field: $field'})';
}

/// One immutable outcome of a practice session — the contract local to this
/// repository (R19 §0.0/2. pont: az outcome-rekord ALAKJA helyi, nem domain).
///
/// A real domain `PracticeOutcome` may replace this once an
/// application/domain consumer needs the shape; that is out of scope here
/// (ADR 0267, brief §3). [id] is the dedup key for the idempotent
/// `appendOutcome` (A4).
final class PracticeOutcome {
  const PracticeOutcome({
    required this.id,
    required this.planId,
    required this.revisionId,
    required this.recordedAt,
    required this.durationMinutes,
    required this.completedBlockCount,
    required this.plannedBlockCount,
    required this.summary,
  });

  final OutcomeId id;
  final PlanId planId;
  final RevisionId revisionId;
  final DateTime recordedAt;
  final int durationMinutes;
  final int completedBlockCount;
  final int plannedBlockCount;
  final String summary;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.toJson(),
    'planId': planId.toJson(),
    'revisionId': revisionId.toJson(),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'durationMinutes': durationMinutes,
    'completedBlockCount': completedBlockCount,
    'plannedBlockCount': plannedBlockCount,
    'summary': summary,
  };

  static PracticeOutcome fromJson(Map<String, Object?> json) {
    final serializer = const PracticePlanSerializer();
    return PracticeOutcome(
      id: OutcomeId.fromJson(json['id']),
      planId: PlanId.fromJson(json['planId']),
      revisionId: RevisionId.fromJson(json['revisionId']),
      recordedAt: DateTime.parse(
        serializer._requireText(json['recordedAt'], 'recordedAt'),
      ).toUtc(),
      durationMinutes: serializer._requirePositiveInt(
        json['durationMinutes'],
        'durationMinutes',
      ),
      completedBlockCount: serializer._requireNonNegativeInt(
        json['completedBlockCount'],
        'completedBlockCount',
      ),
      plannedBlockCount: serializer._requirePositiveInt(
        json['plannedBlockCount'],
        'plannedBlockCount',
      ),
      summary: serializer._requireText(json['summary'], 'summary'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PracticeOutcome &&
      id == other.id &&
      planId == other.planId &&
      revisionId == other.revisionId &&
      recordedAt == other.recordedAt &&
      durationMinutes == other.durationMinutes &&
      completedBlockCount == other.completedBlockCount &&
      plannedBlockCount == other.plannedBlockCount &&
      summary == other.summary;

  @override
  int get hashCode => Object.hash(
    id,
    planId,
    revisionId,
    recordedAt,
    durationMinutes,
    completedBlockCount,
    plannedBlockCount,
    summary,
  );
}

/// The local pointer that names the currently-active plan + revision.
///
/// Two fields only. The pointer is a single small JSON object under
/// [LocalPracticePlanRepository.activePointerKey] and is the *last* thing
/// written on `activate(plan)` — the immutable revision record is fully
/// present before the pointer moves.
final class ActivePlanPointer {
  const ActivePlanPointer({required this.planId, required this.revisionId});

  final PlanId planId;
  final RevisionId revisionId;

  Map<String, Object?> toJson() => <String, Object?>{
    'planId': planId.toJson(),
    'revisionId': revisionId.toJson(),
  };

  static ActivePlanPointer fromJson(Map<String, Object?> json) =>
      ActivePlanPointer(
        planId: PlanId.fromJson(json['planId']),
        revisionId: RevisionId.fromJson(json['revisionId']),
      );

  @override
  bool operator ==(Object other) =>
      other is ActivePlanPointer &&
      planId == other.planId &&
      revisionId == other.revisionId;

  @override
  int get hashCode => Object.hash(planId, revisionId);
}

/// A stored revision: the plan snapshot + the small revision metadata kept
/// outside the snapshot (number, reason, createdAt, previous).
final class ArchivedRevision {
  const ArchivedRevision({
    required this.id,
    required this.planId,
    required this.number,
    required this.createdAt,
    required this.reason,
    required this.previousRevisionId,
    required this.snapshot,
  });

  final RevisionId id;
  final PlanId planId;
  final int number;
  final DateTime createdAt;
  final PlanRevisionReason reason;
  final RevisionId? previousRevisionId;
  final AdaptivePracticePlan snapshot;
}

/// Draft plan being assembled by the wizard — same domain shape as the
/// active plan, kept under a separate key.
final class PracticePlanDraftEnvelope {
  const PracticePlanDraftEnvelope({
    required this.draftKey,
    required this.plan,
    required this.savedAt,
  });

  final String draftKey;
  final AdaptivePracticePlan plan;
  final DateTime savedAt;
}

/// The local codec for every persisted record.
///
/// Stateless: one instance can be shared. The checksum algorithm is
/// non-injectable on purpose — the goal is "every copy of this build reads
/// the same checksum", not "any algorithm we ever want to swap".
///
/// The [migrator] gates the envelope's `schemaVersion` on every read (§5.6):
/// * `> migrator.currentSupportedSchemaVersion` is a controlled rejection —
///   the body is never decoded for a build that does not understand it.
/// * `== migrator.currentSupportedSchemaVersion` is read unchanged.
/// * `< migrator.currentSupportedSchemaVersion` is routed through the
///   forward-migration path **before** the checksum is verified, so the
///   checksum is checked against the migrated body, never silently against
///   the original.
class PracticePlanSerializer {
  const PracticePlanSerializer({this.migrator = const PracticePlanMigrator()});

  /// Schema-version gate used by [openEnvelope]. Defaults to a const
  /// [PracticePlanMigrator]; injection is supported for tests.
  final PracticePlanMigrator migrator;

  /// What `encode*` writes into the envelope's `schemaVersion`.
  static const int currentEnvelopeSchemaVersion = 1;

  // ---------------------------------------------------------------------
  // Encoding
  // ---------------------------------------------------------------------

  Map<String, Object?> encodePlanRecord(AdaptivePracticePlan plan) =>
      _envelope(kind: PracticePlanRecordKind.plan, body: _planToBody(plan));

  Map<String, Object?> encodeRevisionRecord(ArchivedRevision revision) {
    final body = <String, Object?>{
      'id': revision.id.toJson(),
      'planId': revision.planId.toJson(),
      'number': revision.number,
      'createdAt': revision.createdAt.toUtc().toIso8601String(),
      'reason': revision.reason.code,
      'previousRevisionId': revision.previousRevisionId?.toJson(),
      'snapshot': _planToBody(revision.snapshot),
    };
    return _envelope(kind: PracticePlanRecordKind.revision, body: body);
  }

  Map<String, Object?> encodeOutcomeRecord(PracticeOutcome outcome) =>
      _envelope(kind: PracticePlanRecordKind.outcome, body: outcome.toJson());

  Map<String, Object?> encodeArchivedRevisionsIndex(List<RevisionId> ids) =>
      _envelope(
        kind: PracticePlanRecordKind.archivedRevisionIndex,
        body: <String, Object?>{
          'revisionIds': [for (final id in ids) id.toJson()],
        },
      );

  Map<String, Object?> encodeArchivedOutcomesIndex(List<OutcomeId> ids) =>
      _envelope(
        kind: PracticePlanRecordKind.archivedOutcomeIndex,
        body: <String, Object?>{
          'outcomeIds': [for (final id in ids) id.toJson()],
        },
      );

  Map<String, Object?> encodeActivePointer(ActivePlanPointer pointer) =>
      _envelope(
        kind: PracticePlanRecordKind.activePointer,
        body: pointer.toJson(),
      );

  Map<String, Object?> encodeDraft(PracticePlanDraftEnvelope draft) =>
      _envelope(
        kind: PracticePlanRecordKind.draft,
        body: <String, Object?>{
          'draftKey': draft.draftKey,
          'savedAt': draft.savedAt.toUtc().toIso8601String(),
          'plan': _planToBody(draft.plan),
        },
      );

  // ---------------------------------------------------------------------
  // Decoding
  // ---------------------------------------------------------------------

  /// Opens the envelope only — gates **schemaVersion** through [migrator],
  /// then checks shape and **the checksum** (§5.6).
  ///
  /// Order matters:
  /// 1. Type-validate the integer `schemaVersion`.
  /// 2. Ask [migrator] whether the version is readable. A
  ///    `> currentSupportedSchemaVersion` envelope throws
  ///    [PracticePlanMigratorException] BEFORE the body is even checked,
  ///    never a best-effort decode.
  /// 3. Older envelopes go through `migrator.migrateEnvelope` BEFORE the
  ///    checksum is computed — so the checksum verifies against the
  ///    migrated body, not the original.
  /// 4. Shape (`kind`/`body`/`checksum` present) and checksum
  ///    consistency are verified last.
  Envelope openEnvelope(Object? envelope) {
    if (envelope is! Map) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.notAnObject,
      );
    }
    final asMap = Map<String, dynamic>.from(envelope);
    final rawVersion = asMap['schemaVersion'];
    if (rawVersion == null) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.schemaVersionMissing,
        field: 'schemaVersion',
      );
    }
    if (rawVersion is! int) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.schemaVersionNotInt,
        field: 'schemaVersion',
      );
    }
    // Migrator gate: too-new envelopes never reach body decoding.
    // Older envelopes get migrated forward BEFORE checksum verification.
    migrator.ensureSupported(envelopeSchemaVersion: rawVersion);
    final Map<String, dynamic> working =
        rawVersion < PracticePlanMigrator.currentSupportedSchemaVersion
        ? Map<String, dynamic>.from(
            migrator.migrateEnvelope(asMap as Map<String, Object?>),
          )
        : asMap;
    final workingVersion = working['schemaVersion'] as int;
    final kind = working['kind'];
    if (kind is! String || kind.isEmpty) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.kindMissing,
        field: 'kind',
      );
    }
    final body = working['body'];
    if (body is! Map) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.bodyMissing,
        field: 'body',
      );
    }
    final checksum = working['checksum'];
    if (checksum is! String || checksum.isEmpty) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.checksumMissing,
        field: 'checksum',
      );
    }
    final bodyMap = Map<String, dynamic>.from(body);
    final expected = _computeChecksum(bodyMap);
    if (!_constantTimeEquals(expected, checksum)) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.checksumMismatch,
        field: 'checksum',
      );
    }
    return Envelope(
      envelopeSchemaVersion: workingVersion,
      kind: kind,
      body: bodyMap,
    );
  }

  AdaptivePracticePlan decodePlanRecord(
    Map<String, Object?> envelope, {
    required ExerciseCandidateResolver resolveCandidate,
  }) {
    final opened = openEnvelope(envelope);
    if (opened.kind != PracticePlanRecordKind.plan &&
        opened.kind != PracticePlanRecordKind.revision) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.kindUnknown,
        field: 'kind:${opened.kind}',
      );
    }
    final snapshotRaw = opened.kind == PracticePlanRecordKind.revision
        ? opened.body['snapshot']
        : opened.body;
    return _planFromBody(
      _asMap(
        snapshotRaw,
        opened.kind == PracticePlanRecordKind.revision ? 'snapshot' : 'body',
      ),
      resolveCandidate: resolveCandidate,
    );
  }

  ArchivedRevision decodeRevisionRecord(
    Map<String, Object?> envelope, {
    required ExerciseCandidateResolver resolveCandidate,
  }) {
    final opened = openEnvelope(envelope);
    if (opened.kind != PracticePlanRecordKind.revision) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.kindUnknown,
        field: 'kind:${opened.kind}',
      );
    }
    final body = opened.body;
    final previousRaw = body['previousRevisionId'];
    return ArchivedRevision(
      id: RevisionId.fromJson(body['id']),
      planId: PlanId.fromJson(body['planId']),
      number: _requirePositiveInt(body['number'], 'number'),
      createdAt: DateTime.parse(
        _requireText(body['createdAt'], 'createdAt'),
      ).toUtc(),
      reason: _decodeReason(_requireText(body['reason'], 'reason')),
      previousRevisionId: previousRaw == null
          ? null
          : RevisionId.fromJson(previousRaw),
      snapshot: _planFromBody(
        _asMap(body['snapshot'], 'snapshot'),
        resolveCandidate: resolveCandidate,
      ),
    );
  }

  PracticeOutcome decodeOutcomeRecord(Map<String, Object?> envelope) {
    final opened = openEnvelope(envelope);
    if (opened.kind != PracticePlanRecordKind.outcome) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.kindUnknown,
        field: 'kind:${opened.kind}',
      );
    }
    return PracticeOutcome.fromJson(opened.body);
  }

  List<RevisionId> decodeArchivedRevisionsIndex(Map<String, Object?> envelope) {
    final opened = openEnvelope(envelope);
    if (opened.kind != PracticePlanRecordKind.archivedRevisionIndex) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.kindUnknown,
        field: 'kind:${opened.kind}',
      );
    }
    return _decodeIdList(
      opened.body['revisionIds'],
      field: 'revisionIds',
      decode: RevisionId.fromJson,
    );
  }

  List<OutcomeId> decodeArchivedOutcomesIndex(Map<String, Object?> envelope) {
    final opened = openEnvelope(envelope);
    if (opened.kind != PracticePlanRecordKind.archivedOutcomeIndex) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.kindUnknown,
        field: 'kind:${opened.kind}',
      );
    }
    return _decodeIdList(
      opened.body['outcomeIds'],
      field: 'outcomeIds',
      decode: OutcomeId.fromJson,
    );
  }

  ActivePlanPointer decodeActivePointer(Map<String, Object?> envelope) {
    final opened = openEnvelope(envelope);
    if (opened.kind != PracticePlanRecordKind.activePointer) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.kindUnknown,
        field: 'kind:${opened.kind}',
      );
    }
    return ActivePlanPointer.fromJson(opened.body);
  }

  PracticePlanDraftEnvelope decodeDraft(
    Map<String, Object?> envelope, {
    required ExerciseCandidateResolver resolveCandidate,
  }) {
    final opened = openEnvelope(envelope);
    if (opened.kind != PracticePlanRecordKind.draft) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.kindUnknown,
        field: 'kind:${opened.kind}',
      );
    }
    final body = opened.body;
    return PracticePlanDraftEnvelope(
      draftKey: _requireText(body['draftKey'], 'draftKey'),
      savedAt: DateTime.parse(_requireText(body['savedAt'], 'savedAt')).toUtc(),
      plan: _planFromBody(
        _asMap(body['plan'], 'plan'),
        resolveCandidate: resolveCandidate,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Plan body codec
  // ---------------------------------------------------------------------

  Map<String, Object?> _planToBody(AdaptivePracticePlan plan) =>
      <String, Object?>{
        'schemaVersion': plan.schemaVersion,
        'id': plan.id.toJson(),
        'status': plan.status.code,
        'title': plan.title,
        'createdAt': plan.createdAt.toIso8601String(),
        'startDate': _dateToJson(plan.startDate),
        'endDate': _dateToJson(plan.endDate),
        'goals': [for (final goal in plan.goals) _goalToJson(goal)],
        'days': [for (final day in plan.days) day.toJson()],
        'activeRevisionId': plan.activeRevisionId.toJson(),
        'generationProvenance': plan.generationProvenance.toJson(),
        'policyVersions': plan.policyVersions,
      };

  AdaptivePracticePlan _planFromBody(
    Map<String, Object?> json, {
    required ExerciseCandidateResolver resolveCandidate,
  }) => AdaptivePracticePlan.fromJson(json, resolveCandidate: resolveCandidate);

  Map<String, Object?> _goalToJson(PracticeGoal goal) => <String, Object?>{
    'id': goal.id.toJson(),
    'type': goal.type.code,
    'priority': goal.priority.code,
    'status': goal.status.code,
    'createdAt': goal.createdAt.toIso8601String(),
    'targetDate': goal.targetDate == null
        ? null
        : _dateToJson(goal.targetDate!),
    'skillIds': goal.skillIds,
    'songReference': goal.songReference,
    'metricTarget': goal.metricTarget == null
        ? null
        : _metricTargetToJson(goal.metricTarget!),
    'userNote': goal.userNote,
    'normalizedTargetId': goal.normalizedTargetId,
  };

  Map<String, Object?> _metricTargetToJson(MetricTarget target) =>
      <String, Object?>{
        'metricCode': target.metricCode,
        'direction': target.direction.code,
        'threshold': target.threshold,
        'measurementCapability': target.measurementCapability,
        'minimumConfidence': target.minimumConfidence,
        'minimumSampleCount': target.minimumSampleCount,
        'targetDate': target.targetDate == null
            ? null
            : _dateToJson(target.targetDate!),
      };

  Map<String, int> _dateToJson(LocalDate date) => <String, int>{
    'year': date.year,
    'month': date.month,
    'day': date.day,
  };

  // ---------------------------------------------------------------------
  // Envelope (version + body + checksum)
  // ---------------------------------------------------------------------

  Map<String, Object?> _envelope({
    required String kind,
    required Map<String, Object?> body,
  }) {
    final checksum = _computeChecksum(body);
    return <String, Object?>{
      'schemaVersion': currentEnvelopeSchemaVersion,
      'kind': kind,
      'body': body,
      'checksum': checksum,
    };
  }

  String _computeChecksum(Map<String, Object?> body) {
    final canonical = jsonEncode(_canonicalize(body));
    return crypto.sha256.convert(utf8.encode(canonical)).toString();
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  PlanRevisionReason _decodeReason(String code) {
    for (final value in PlanRevisionReason.values) {
      if (value.code == code) return value;
    }
    throw PracticePlanSerializerException(
      PracticePlanSerializerErrorCode.bodyInvalid,
      field: 'reason:$code',
    );
  }

  Map<String, Object?> _asMap(Object? value, String field) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw PracticePlanSerializerException(
      PracticePlanSerializerErrorCode.bodyInvalid,
      field: field,
    );
  }

  String _requireText(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.bodyInvalid,
        field: field,
      );
    }
    return value;
  }

  int _requirePositiveInt(Object? value, String field) {
    if (value is! num || value.toInt() != value || value.toInt() < 1) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.bodyInvalid,
        field: field,
      );
    }
    return value.toInt();
  }

  int _requireNonNegativeInt(Object? value, String field) {
    if (value is! num || value.toInt() != value || value.toInt() < 0) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.bodyInvalid,
        field: field,
      );
    }
    return value.toInt();
  }

  List<T> _decodeIdList<T>(
    Object? raw, {
    required String field,
    required T Function(Object?) decode,
  }) {
    if (raw is! List) {
      throw PracticePlanSerializerException(
        PracticePlanSerializerErrorCode.bodyInvalid,
        field: field,
      );
    }
    return [
      for (final entry in raw)
        if (entry is String)
          decode(entry)
        else
          throw PracticePlanSerializerException(
            PracticePlanSerializerErrorCode.bodyInvalid,
            field: '$field[]',
          ),
    ];
  }
}

/// The shape returned by [PracticePlanSerializer.openEnvelope].
final class Envelope {
  const Envelope({
    required this.envelopeSchemaVersion,
    required this.kind,
    required this.body,
  });

  final int envelopeSchemaVersion;
  final String kind;
  final Map<String, dynamic> body;
}

/// Recursively sorts every [Map]'s keys, so the canonical JSON encoding of
/// the body does not depend on insertion order. This is what keeps the
/// checksum stable across builds that happen to encode maps in a different
/// order (ADR 0259 §2 principle applied to the local store).
Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sortedKeys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in sortedKeys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _canonicalize(item)];
  }
  return value;
}
