/// User-initiated export of every practice-planning datum the app holds
/// on the learner's device (E07-R29 §5.5, §6.1 export scope guard).
///
/// The export is a self-contained JSON document written to the app's
/// private cache directory. It is **not** uploaded to any network by
/// this use case — the user must share the file themselves if they want
/// to keep a copy off-device. The export deliberately mirrors the
/// delete-all scope, so what the user can take away is exactly what
/// they can wipe.
library;

import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import '../../../../core/foundation/app_result.dart';
import '../../data/local/local_practice_plan_repository.dart';
import '../../data/local/practice_plan_serializer.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/skill_evidence.dart';
import '../../domain/repository/practice_evidence_repository.dart';

/// Result of a successful export: the path the file was written to.
/// The privacy screen surfaces this name so the learner can share /
/// inspect it.
final class ExportPracticePlanningDataResult {
  const ExportPracticePlanningDataResult({
    required this.fileName,
    required this.byteCount,
    required this.evidenceRecordCount,
  });

  final String fileName;
  final int byteCount;
  final int evidenceRecordCount;
}

/// Returns a plan with every `comfort`-category [LearnerConstraint]
/// removed (its `value` is the free-text "comfort note") and with the
/// `userNote` of every goal blanked. The export deliberately never
/// carries free-text learner input (ADR 0260 §4): the on-device export
/// file is something the learner may ultimately share, so it must not
/// leak the comfort note.
/// Strips comfort-category constraints' `value` fields and every goal's
/// `userNote` from an already-encoded envelope. The envelope may be either
/// the active-plan shape (`body = {...plan fields}`) or the draft-envelope
/// shape (`body = {draftKey, savedAt, plan: {...plan fields}}`).
/// The export deliberately never carries free-text learner input
/// (ADR 0260 §4): the on-device export file is something the learner
/// may ultimately share, so it must not leak the comfort note.
Map<String, Object?> _redactPlanJson(Map<String, Object?> encoded) {
  final body = encoded['body'];
  if (body is! Map<String, Object?>) return encoded;

  // Locate the plan-body sub-tree: either `body` itself (active) or
  // `body['plan']` (draft envelope).
  Map<String, Object?>? planBody;
  if (body.containsKey('goals') && body['goals'] is List) {
    planBody = body;
  } else if (body['plan'] is Map<String, Object?>) {
    planBody = body['plan'] as Map<String, Object?>;
  }
  if (planBody == null) return encoded;

  if (planBody['constraints'] is Map<String, Object?>) {
    final constraints = <String, Object?>{
      for (final entry
          in (planBody['constraints'] as Map<String, Object?>).entries)
        entry.key: entry.value,
    };
    final values = constraints['values'];
    if (values is List) {
      constraints['values'] = <Object?>[
        for (final raw in values)
          if (raw is Map<String, Object?>)
            (raw['category'] == 'comfort')
                ? <String, Object?>{...raw, 'value': ''}
                : raw
          else
            raw,
      ];
    }
    planBody['constraints'] = constraints;
  }

  if (planBody['goals'] is List) {
    planBody['goals'] = <Object?>[
      for (final raw in (planBody['goals'] as List))
        if (raw is Map<String, Object?>)
          <String, Object?>{...raw, 'userNote': ''}
        else
          raw,
    ];
  }
  return encoded;
}

/// Pure use case: no logging, no telemetry. Free-text "comfort notes"
/// are NEVER present in the export — the planner does not persist them
/// (ADR 0260 §4, ADR 0265 §3).
class ExportPracticePlanningData {
  ExportPracticePlanningData({
    required this.planRepository,
    required this.evidenceRepository,
    required this.cacheDirectory,
    required this.clock,
    this.serializer = const PracticePlanSerializer(),
    this.generatorVersion = 'e07-r29',
    this.fileWriter,
  });

  final LocalPracticePlanRepository planRepository;
  final PracticeEvidenceRepository evidenceRepository;
  final Future<Directory> Function() cacheDirectory;
  final DateTime Function() clock;
  final PracticePlanSerializer serializer;
  final String generatorVersion;

  /// Optional file writer override for tests. Production code leaves
  /// this null and uses [File.writeAsBytes] directly.
  final Future<void> Function(String path, List<int> bytes)? fileWriter;

  Future<AppResult<ExportPracticePlanningDataResult>> call() async {
    final snapshot = await planRepository.exportSnapshot();
    if (snapshot.isFailure) {
      return Failure<ExportPracticePlanningDataResult>(snapshot.failureOrNull!);
    }
    final snap = snapshot.valueOrNull!;

    // Collect every evidence record the planner wrote, deduped by
    // `sourceOutcomeId`. The planner's archive holds the source-of-truth
    // for which outcome ids belong to which plan; the export restricts
    // itself to those.
    final evidence = <SkillEvidence>[];
    final visited = <String>{};
    void collect(PlanId planId) {
      final log = snap.archive[planId];
      if (log == null) return;
      for (final outcome in log.outcomes) {
        if (!visited.add(outcome.id.value)) continue;
        final e = evidenceRepository.findByOutcomeId(outcome.id);
        if (e != null) evidence.add(e);
      }
    }

    for (final planId in snap.archive.keys) {
      collect(planId);
    }
    final activePlan = snap.activePlan;
    if (activePlan != null) collect(activePlan.id);

    final payload = <String, Object?>{
      'meta': <String, Object?>{
        'kind': 'strumsight.practice_planning_export',
        'generator': generatorVersion,
        'exportedAt': clock().toUtc().toIso8601String(),
      },
      'active': <String, Object?>{
        'pointer': snap.activePointer == null
            ? null
            : <String, Object?>{
                'planId': snap.activePointer!.planId.value,
                'revisionId': snap.activePointer!.revisionId.value,
              },
        'plan': snap.activePlan == null
            ? null
            : _redactPlanJson(serializer.encodePlanRecord(snap.activePlan!)),
      },
      'drafts': <String, Object?>{
        for (final entry in snap.drafts.entries)
          entry.key: _redactPlanJson(
            serializer.encodeDraft(
              PracticePlanDraftEnvelope(
                draftKey: entry.key,
                plan: entry.value,
                savedAt: clock().toUtc(),
              ),
            ),
          ),
      },
      'archive': <String, Object?>{
        for (final entry in snap.archive.entries)
          entry.key.value: <String, Object?>{
            'revisions': <Object?>[
              for (final r in entry.value.revisions)
                serializer.encodeRevisionRecord(r),
            ],
            'outcomes': <Object?>[
              for (final o in entry.value.outcomes)
                serializer.encodeOutcomeRecord(o),
            ],
          },
      },
      'evidence': <Object?>[for (final e in evidence) _evidenceToJson(e)],
    };

    final encoded = utf8.encode(jsonEncode(payload));
    final dir = await cacheDirectory();
    final timestamp = clock().toUtc().millisecondsSinceEpoch;
    final fileName = 'strumsight-planning-export-$timestamp.json';
    final fullPath = '${dir.path}${Platform.pathSeparator}$fileName';

    final writer = fileWriter;
    if (writer != null) {
      await writer(fullPath, encoded);
    } else {
      await File(fullPath).writeAsBytes(encoded, flush: true);
    }

    return Success<ExportPracticePlanningDataResult>(
      ExportPracticePlanningDataResult(
        fileName: fileName,
        byteCount: encoded.length,
        evidenceRecordCount: evidence.length,
      ),
    );
  }

  Object? _evidenceToJson(SkillEvidence evidence) {
    // Note: SkillEvidence.discomfort.note is the discomfort *category
    // label* (e.g. "mild"), NOT free text. Per ADR 0260 §4 + ADR 0265
    // §3 the free-text "comfort note" never reaches the evidence
    // record, so the JSON export never has to redact it.
    final performance = evidence.performance;
    final discomfort = evidence.discomfort;
    return <String, Object?>{
      'skillId': evidence.skillId,
      'source': evidence.source.name,
      'sourceOutcomeId': evidence.sourceOutcomeId.value,
      'measurementVersion': evidence.measurementVersion,
      'measuredAt': evidence.measuredAt.toIso8601String(),
      'capturedAt': evidence.capturedAt.toIso8601String(),
      'confidence': evidence.confidence,
      if (evidence.validUntil != null)
        'validUntil': evidence.validUntil!.toIso8601String(),
      if (performance != null)
        'performance': <String, Object?>{
          'metricCode': performance.metricCode,
          'value': performance.value,
        },
      if (discomfort != null)
        'discomfort': <String, Object?>{'category': discomfort.category.name},
    };
  }
}
