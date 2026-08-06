import 'dart:convert';
import 'dart:io';

import 'package:strumsight/features/ai_tutor/domain/models/tutor_source_ref.dart';
import 'package:strumsight/features/ai_tutor/domain/services/tutor_claim_validator.dart';
import 'package:strumsight/features/ai_tutor/domain/services/tutor_safety_policy.dart';

/// Evaluates tutor safety output against pinned dataset entries.
///
/// Usage: dart run evaluation/tutor/run_eval.dart [--dataset <path>]
///
/// Computes four metrics:
/// - schema_validity: fraction of entries with valid claim type taxonomy
/// - action_validity: fraction of entries with valid evidence-backed actions
/// - groundedness: fraction of entries where claim validator matches expected
/// - safety_coverage: fraction of safety categories correctly detected
///
/// Exit 0 if all metrics >= thresholds, 1 otherwise.
void main(List<String> arguments) async {
  String datasetPath = 'evaluation/tutor/datasets/safety_categories.json';

  for (var i = 0; i < arguments.length; i++) {
    if (arguments[i] == '--dataset' && i + 1 < arguments.length) {
      datasetPath = arguments[i + 1];
      i++;
    } else if (arguments[i] == '--help') {
      stdout.writeln(
        'Usage: dart run evaluation/tutor/run_eval.dart [--dataset <path>]',
      );
      return;
    }
  }

  final datasetFile = File(datasetPath);
  if (!await datasetFile.exists()) {
    stderr.writeln('Dataset not found: $datasetPath');
    exitCode = 2;
    return;
  }

  final json =
      jsonDecode(await datasetFile.readAsString()) as Map<String, dynamic>;
  final thresholds = Map<String, num>.from(json['thresholds'] as Map);
  final entries = List<Map<String, dynamic>>.from(json['entries'] as List);

  const policy = TutorSafetyPolicy();
  const claimValidator = TutorClaimValidator();

  final trustedSourceRefs = <TutorSourceRef>[
    const TutorSourceRef(
      sourceId: 'kb-guitar-v2',
      title: 'Guitar Knowledge Base',
      locale: 'en',
      topic: 'chords',
      knowledgeVersion: 2,
      chunkIndex: 0,
      chunkHash: 'abc123',
    ),
    const TutorSourceRef(
      sourceId: 'kb-guitar-v2',
      title: 'Guitar Knowledge Base',
      locale: 'en',
      topic: 'scales',
      knowledgeVersion: 2,
      chunkIndex: 1,
      chunkHash: 'def456',
    ),
  ];

  var safetyPassed = 0;
  var groundedPassed = 0;
  var groundedTotal = 0;
  var schemaPassed = 0;
  var schemaTotal = 0;
  var actionPassed = 0;
  var actionTotal = 0;
  var totalEntries = entries.length;

  final failures = <String>[];

  for (final entry in entries) {
    final id = entry['id'] as String;
    final outputText = entry['outputText'] as String;
    final hasInjection = entry['hasInjection'] as bool? ?? false;
    final hasInventedMetric = entry['hasInventedMetric'] as bool? ?? false;
    final hasCameraClaim = entry['hasCameraClaim'] as bool? ?? false;
    final expectedBlocked = List<String>.from(
      entry['expectedBlockedCategories'] as List,
    );
    final claims = List<Map<String, dynamic>>.from(
      entry['claims'] as List? ?? [],
    );

    // Safety policy evaluation
    final safetyResult = policy.evaluate(
      TutorSafetyPolicyRequest(
        outputText: outputText,
        hasInjection: hasInjection,
        hasInventedMetric: hasInventedMetric,
        hasCameraClaim: hasCameraClaim,
        isRateLimited: false,
        isUsageExceeded: false,
      ),
    );

    final actualBlocked = safetyResult.blockedCategories
        .map((c) => c.name)
        .toSet();
    final expectedSet = expectedBlocked.toSet();

    if (actualBlocked.containsAll(expectedSet) &&
        expectedSet.containsAll(actualBlocked)) {
      safetyPassed++;
    } else {
      failures.add(
        '$id: safety mismatch — expected $expectedSet, got $actualBlocked',
      );
    }

    // Claim validation — groundedness
    if (claims.isNotEmpty) {
      groundedTotal++;
      final expectedClaimValid = entry['expectedClaimValid'] as bool? ?? true;

      final tutorClaims = claims.map(
        (c) => TutorClaim(
          type: c['type'] as String,
          evidenceRefs: Set<String>.from(
            List<String>.from(c['evidenceRefs'] as List? ?? []),
          ),
        ),
      );

      final claimResult = claimValidator.validate(
        claims: tutorClaims,
        trustedSourceRefs: trustedSourceRefs,
      );

      // Groundedness: overall claim validity vs expected
      if (claimResult.isValid == expectedClaimValid) {
        groundedPassed++;
      } else {
        failures.add(
          '$id: groundedness mismatch — expected '
          'isValid=$expectedClaimValid, got ${claimResult.isValid} '
          '(issues: ${claimResult.issues.map((i) => i.name)})',
        );
      }

      // Schema validity: claim types must be in the grounding taxonomy.
      // An entry is schema-valid iff it has NO unsupportedClaim issues.
      schemaTotal++;
      final expectedSchemaValid =
          entry['expectedSchemaValid'] as bool? ?? true;
      final actualSchemaValid =
          !claimResult.issues.contains(TutorClaimValidationIssue.unsupportedClaim);

      if (actualSchemaValid == expectedSchemaValid) {
        schemaPassed++;
      } else {
        failures.add(
          '$id: schema mismatch — expected '
          'schemaValid=$expectedSchemaValid, got $actualSchemaValid',
        );
      }

      // Action validity: evidence-required claims must have trusted refs.
      // An entry is action-valid iff it has NO unsupportedClaimEvidence issues.
      actionTotal++;
      final expectedActionValid =
          entry['expectedActionValid'] as bool? ?? true;
      final actualActionValid = !claimResult.issues
          .contains(TutorClaimValidationIssue.unsupportedClaimEvidence);

      if (actualActionValid == expectedActionValid) {
        actionPassed++;
      } else {
        failures.add(
          '$id: action mismatch — expected '
          'actionValid=$expectedActionValid, got $actualActionValid',
        );
      }
    }
  }

  // Compute metrics
  final safetyCoverage = totalEntries > 0
      ? (safetyPassed / totalEntries * 100).round()
      : 0;
  final groundedness = groundedTotal > 0
      ? (groundedPassed / groundedTotal * 100).round()
      : 100;
  final schemaValidity = schemaTotal > 0
      ? (schemaPassed / schemaTotal * 100).round()
      : 100;
  final actionValidity = actionTotal > 0
      ? (actionPassed / actionTotal * 100).round()
      : 100;

  // Print report
  stdout.writeln('=== Tutor Safety Evaluation Report ===');
  stdout.writeln('Dataset: $datasetPath');
  stdout.writeln('Entries: $totalEntries');
  stdout.writeln('');
  stdout.writeln(
    'schema_validity:  $schemaValidity% '
    '(threshold: ${thresholds['schema_validity']}%)',
  );
  stdout.writeln(
    'action_validity:  $actionValidity% '
    '(threshold: ${thresholds['action_validity']}%)',
  );
  stdout.writeln(
    'groundedness:     $groundedness% '
    '(threshold: ${thresholds['groundedness']}%)',
  );
  stdout.writeln(
    'safety_coverage:  $safetyCoverage% '
    '(threshold: ${thresholds['safety_coverage']}%)',
  );
  stdout.writeln('');

  if (failures.isNotEmpty) {
    stdout.writeln('Failures:');
    for (final f in failures) {
      stdout.writeln('  - $f');
    }
    stdout.writeln('');
  }

  // Check thresholds
  var allGreen = true;

  if (schemaValidity < (thresholds['schema_validity'] ?? 100)) {
    stdout.writeln('FAIL: schema_validity below threshold');
    allGreen = false;
  }
  if (actionValidity < (thresholds['action_validity'] ?? 100)) {
    stdout.writeln('FAIL: action_validity below threshold');
    allGreen = false;
  }
  if (groundedness < (thresholds['groundedness'] ?? 100)) {
    stdout.writeln('FAIL: groundedness below threshold');
    allGreen = false;
  }
  if (safetyCoverage < (thresholds['safety_coverage'] ?? 100)) {
    stdout.writeln('FAIL: safety_coverage below threshold');
    allGreen = false;
  }

  if (allGreen) {
    stdout.writeln('PASS: All metrics above thresholds');
  }

  exitCode = allGreen ? 0 : 1;
}
