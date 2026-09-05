// Augmentation manifest guard (E14-R19, ADR 0525).
//
// This round ships NO production Dart entry point (`lib/` and `tool/` are
// both in the forbidden zone) — so, as the same deliberate, bounded
// exception used in E14-R18 (ADR 0517 D8, precedent L631,
// test/tooling/joint_io_schema_test.dart), the hand-written validator lives
// ENTIRELY in this test file. There is also no separate JSON-Schema
// document in this round's allowed-files list, so unlike the joint-IO guard
// this validator is a single hand-written field-by-field + cross-field
// check (ADR 0525 D5/D6/D8) rather than a generic-schema layer plus a
// semantic layer.
//
// The CI-side fixture (`evaluation/recognition/fixtures/
// augmentation_manifest_sample.json`) mirrors the ACTUAL manifest the
// Python side ships (`ml/augmentation_manifest.json`, built + validated by
// `ml.augment.build_manifest`/`validate_manifest`) — CI has no Python/
// TensorFlow interpreter (round brief R7), so this Dart guard is the
// CI-side mirror of that Python contract, not a re-run of it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('A1 — the real, shipped fixture validates cleanly against the real '
      'contract (sanity: the manifest we ship is internally consistent)', () {
    test('the real augmentation_manifest_sample.json validates cleanly', () {
      final report = validateAugmentationManifest(
        documentJsonText: _realFixtureText(),
      );

      expect(report.isClean, isTrue, reason: report.formatIssues());
    });

    test('the shipped composite recipe row is "rejected" (round brief AC7, '
        'ADR 0525 D7) — the ma szállított recept nem javít', () {
      final doc = _fixture();
      final transforms = (doc['transforms']! as List)
          .cast<Map<String, Object?>>();
      final composite = transforms.firstWhere(
        (t) => t['name'] == 'composite_recipe_r173',
      );
      expect(composite['status'], 'rejected');
    });
  });

  group('A2 — required top-level fields (round brief AC5, ADR 0525 D5): a '
      'missing field is a typed error, never a silent default', () {
    test('a missing seed is rejected', () {
      final doc = _fixture()..remove('seed');
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('seed'));
    });

    test('a non-integer seed is rejected', () {
      final doc = _fixture()..['seed'] = 'forty-two';
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });

    test('a missing transforms list is rejected', () {
      final doc = _fixture()..remove('transforms');
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('transforms'));
    });

    test('an empty transforms list is rejected', () {
      final doc = _fixture()..['transforms'] = <Object?>[];
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });

    test('a missing classRatios block is rejected', () {
      final doc = _fixture()..remove('classRatios');
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('classRatios'));
    });
  });

  group('A3 — each transform entry carries name/enabled/params/status/'
      'measured/reproCommand/measuredCostSeconds (round brief AC5)', () {
    test('a transform missing "status" is rejected', () {
      final doc = _fixture();
      _firstTransform(doc).remove('status');
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('status'));
    });

    test('a transform with an unknown status is rejected — only accepted/'
        'candidate/rejected exist', () {
      final doc = _fixture();
      _firstTransform(doc)['status'] = 'maybe';
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });

    test('enabled must be a bool, not a truthy string', () {
      final doc = _fixture();
      _firstTransform(doc)['enabled'] = 'true';
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });

    test('a missing reproCommand is rejected', () {
      final doc = _fixture();
      _firstTransform(doc).remove('reproCommand');
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });

    test('a missing measuredCostSeconds is rejected — even a "nem mert" row '
        'carries its measured cost (ADR 0525 D6)', () {
      final doc = _fixture();
      _firstTransform(doc).remove('measuredCostSeconds');
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });
  });

  group('A4 — "nem mert" is never numeric 0, and never "accepted" (round '
      'brief AC6, ADR 0525 D6) — this is the anti-reward-hacking gate', () {
    test('a numeric 0 standing in for a missing measurement is rejected', () {
      final doc = _fixture();
      _firstTransform(doc)['measured'] = 0;
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('measured'));
    });

    test('a numeric 0.0 standing in for a missing measurement is rejected '
        'too (not just the int form)', () {
      final doc = _fixture();
      _firstTransform(doc)['measured'] = 0.0;
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });

    test('this is the round\'s mandated falsification cell (round §7.1): '
        'a "nem mert" row carrying status "accepted" is rejected — this is '
        'the literal anti-reward-hacking rule ADR 0525 D6 exists for '
        '(documented in §10 as a RED state this test catches when the '
        'accepted-vs-measured cross-check is removed)', () {
      final doc = _fixture();
      final transform = _firstTransform(doc);
      transform['measured'] = 'nem mért';
      transform['status'] = 'accepted';
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('accepted'));
    });

    test('a "nem mert" row with status "candidate" or "rejected" is fine', () {
      final doc = _fixture();
      final transform = _firstTransform(doc);
      transform['measured'] = 'nem mért';
      transform['status'] = 'rejected';
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isTrue, reason: report.formatIssues());
    });
  });

  group('A5 — a measured row\'s "accepted"/"rejected" status must agree with '
      'its own numbers (ADR 0525 D6) — the status is RECOMPUTED, never '
      'trusted from the document', () {
    test('a measured row claiming "accepted" while every split is a '
        'regression is rejected', () {
      final doc = _fixture();
      final composite = _transformNamed(doc, 'composite_recipe_r173');
      composite['status'] = 'accepted';
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('accepted'));
    });

    test('a measured row with a CLEAN improvement cannot be "rejected"', () {
      final doc = _fixture();
      final composite = _transformNamed(doc, 'composite_recipe_r173');
      composite['status'] = 'rejected';
      (composite['measured']! as Map<String, Object?>)['unseenPlayerSplits'] = [
        {
          'split': 'logoBatch',
          'baseline': 0.60,
          'baselineStdDev': 0.01,
          'treated': 0.70,
          'treatedStdDev': 0.01,
          'delta': 0.10,
        },
      ];
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });

    test('a split whose declared delta disagrees with treated - baseline is '
        'rejected — the number is recomputed, not trusted', () {
      final doc = _fixture();
      final composite = _transformNamed(doc, 'composite_recipe_r173');
      final splits =
          (composite['measured']!
                  as Map<String, Object?>)['unseenPlayerSplits']!
              as List;
      (splits.first as Map<String, Object?>)['delta'] = 999.0;
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('delta'));
    });

    test('the shipped composite recipe cites BOTH measured LOGO deltas from '
        'the round brief (batch -0.0081, live70 -0.0772, R4)', () {
      final doc = _fixture();
      final composite = _transformNamed(doc, 'composite_recipe_r173');
      final splits =
          ((composite['measured']!
                      as Map<String, Object?>)['unseenPlayerSplits']!
                  as List)
              .cast<Map<String, Object?>>();
      final deltas = splits
          .map((s) => (s['delta']! as num).toDouble())
          .toList();
      expect(deltas, containsAll(<double>[-0.0081, -0.0772]));
    });
  });

  group('A6 — classRatios carries BOTH baseline and balanced ratios for '
      'BOTH direction and chord classes (round brief AC5)', () {
    test('a missing "chord" ratio group is rejected', () {
      final doc = _fixture();
      (doc['classRatios']! as Map<String, Object?>).remove('chord');
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('chord'));
    });

    test('a missing "balanced" phase is rejected', () {
      final doc = _fixture();
      (((doc['classRatios']! as Map<String, Object?>)['direction'])!
              as Map<String, Object?>)
          .remove('balanced');
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });

    test('ratios that do not sum to 1.0 are rejected', () {
      final doc = _fixture();
      ((((doc['classRatios']! as Map<String, Object?>)['direction'])!
                  as Map<String, Object?>)['baseline']!
              as Map<String, Object?>)['down'] =
          0.99;
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });
  });

  group('A7 — the two pitch-shift limits stay explicit and DISTINCT (round '
      'brief R11, ADR 0525 D10): the PCM/varispeed ISMIR bound and the CQT '
      'chord-track zero-fill bound are different constraints, not the same '
      'number twice', () {
    test('pcmVarispeedMaxSemitones must be the literal 6', () {
      final doc = _fixture();
      (doc['pitchShiftLimits']!
              as Map<String, Object?>)['pcmVarispeedMaxSemitones'] =
          7;
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });

    test('cqtChordTrackMaxSemitones conflated with the PCM bound (both 6) '
        'is rejected', () {
      final doc = _fixture();
      (doc['pitchShiftLimits']!
              as Map<String, Object?>)['cqtChordTrackMaxSemitones'] =
          6;
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });
  });

  group('A8 — balancing never drops real data (round brief 5.6, ADR 0525 '
      'D8)', () {
    test('dropsRealData: true is rejected — balancing may only weight or '
        'resample', () {
      final doc = _fixture();
      (doc['balancing']! as Map<String, Object?>)['dropsRealData'] = true;
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('dropsRealData'));
    });

    test('a missing balancing.method is rejected', () {
      final doc = _fixture();
      (doc['balancing']! as Map<String, Object?>).remove('method');
      final report = validateAugmentationManifest(
        documentJsonText: jsonEncode(doc),
      );
      expect(report.isClean, isFalse);
    });
  });
}

// --- Fixtures ---------------------------------------------------------

String _realFixtureText() => File(
  '${_findProjectRoot().path}/evaluation/recognition/fixtures/'
  'augmentation_manifest_sample.json',
).readAsStringSync();

/// A fresh, mutable copy of the real fixture document for each test — never
/// shared, so one test's mutation can never leak into another.
Map<String, Object?> _fixture() =>
    jsonDecode(_realFixtureText()) as Map<String, Object?>;

Map<String, Object?> _firstTransform(Map<String, Object?> doc) =>
    ((doc['transforms']! as List).first) as Map<String, Object?>;

Map<String, Object?> _transformNamed(Map<String, Object?> doc, String name) =>
    (doc['transforms']! as List).cast<Map<String, Object?>>().firstWhere(
      (t) => t['name'] == name,
    );

Directory _findProjectRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    final pubspec = File('${candidate.path}/pubspec.yaml');
    final agents = File('${candidate.path}/AGENTS.md');
    if (pubspec.existsSync() && agents.existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not find the StrumSight repository root.');
    }
    candidate = parent;
  }
}

// --- Report types -----------------------------------------------------

final class AugmentationManifestIssue {
  const AugmentationManifestIssue({required this.path, required this.message});

  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

final class AugmentationManifestReport {
  AugmentationManifestReport(List<AugmentationManifestIssue> issues)
    : issues = List.unmodifiable(issues);

  final List<AugmentationManifestIssue> issues;

  bool get isClean => issues.isEmpty;

  String formatIssues() {
    if (isClean) return 'Augmentation manifest OK.';
    final buffer = StringBuffer('Augmentation manifest check failed.');
    for (final issue in issues) {
      buffer
        ..writeln()
        ..write('- $issue');
    }
    return buffer.toString();
  }
}

const _validStatuses = <String>{'accepted', 'candidate', 'rejected'};
const _notMeasured = 'nem mért';

/// Validates an augmentation-manifest document against the ADR 0525 D5/D6/D8
/// contract. Hand-written (round brief R8: no JSON-Schema document is in
/// this round's allowed-files list, and `lib/`/`tool/` are both forbidden).
AugmentationManifestReport validateAugmentationManifest({
  required String documentJsonText,
}) {
  final issues = <AugmentationManifestIssue>[];

  Object? document;
  try {
    document = jsonDecode(documentJsonText);
  } on FormatException catch (error) {
    return AugmentationManifestReport([
      AugmentationManifestIssue(path: r'$', message: 'invalid JSON: $error'),
    ]);
  }
  if (document is! Map<String, Object?>) {
    return AugmentationManifestReport(const [
      AugmentationManifestIssue(
        path: r'$',
        message: 'document root must be a JSON object',
      ),
    ]);
  }

  _validateSeed(document, issues);
  _validateTransforms(document, issues);
  _validateClassRatios(document, issues);
  _validatePitchShiftLimits(document, issues);
  _validateBalancing(document, issues);

  return AugmentationManifestReport(issues);
}

void _validateSeed(
  Map<String, Object?> doc,
  List<AugmentationManifestIssue> issues,
) {
  if (!doc.containsKey('seed')) {
    issues.add(
      const AugmentationManifestIssue(
        path: r'$.seed',
        message: 'missing required field: seed',
      ),
    );
    return;
  }
  if (doc['seed'] is! int) {
    issues.add(
      AugmentationManifestIssue(
        path: r'$.seed',
        message: 'must be an int, got ${doc['seed']}',
      ),
    );
  }
}

void _validateTransforms(
  Map<String, Object?> doc,
  List<AugmentationManifestIssue> issues,
) {
  final transforms = doc['transforms'];
  if (transforms is! List || transforms.isEmpty) {
    issues.add(
      const AugmentationManifestIssue(
        path: r'$.transforms',
        message: 'missing required non-empty field: transforms',
      ),
    );
    return;
  }

  for (var i = 0; i < transforms.length; i++) {
    final entry = transforms[i];
    final path = '\$.transforms[$i]';
    if (entry is! Map<String, Object?>) {
      issues.add(
        AugmentationManifestIssue(path: path, message: 'must be an object'),
      );
      continue;
    }
    for (final field in const [
      'name',
      'enabled',
      'params',
      'status',
      'measured',
      'reproCommand',
      'measuredCostSeconds',
    ]) {
      if (!entry.containsKey(field)) {
        issues.add(
          AugmentationManifestIssue(
            path: path,
            message: 'missing required field: $field',
          ),
        );
      }
    }
    if (issues.any((issue) => issue.path == path)) continue;

    if (entry['name'] is! String || (entry['name']! as String).isEmpty) {
      issues.add(
        AugmentationManifestIssue(
          path: '$path.name',
          message: 'must be a non-empty string',
        ),
      );
    }
    if (entry['enabled'] is! bool) {
      issues.add(
        AugmentationManifestIssue(
          path: '$path.enabled',
          message: 'must be a bool',
        ),
      );
    }
    if (entry['params'] is! Map<String, Object?>) {
      issues.add(
        AugmentationManifestIssue(
          path: '$path.params',
          message: 'must be an object',
        ),
      );
    }
    final status = entry['status'];
    if (status is! String || !_validStatuses.contains(status)) {
      issues.add(
        AugmentationManifestIssue(
          path: '$path.status',
          message: 'must be one of $_validStatuses, got $status',
        ),
      );
    }
    if (entry['reproCommand'] is! String ||
        (entry['reproCommand']! as String).isEmpty) {
      issues.add(
        AugmentationManifestIssue(
          path: '$path.reproCommand',
          message: 'must be a non-empty string',
        ),
      );
    }
    if (entry['measuredCostSeconds'] is! num) {
      issues.add(
        AugmentationManifestIssue(
          path: '$path.measuredCostSeconds',
          message:
              'must be a number — even a "$_notMeasured" row carries '
              'its measured cost (ADR 0525 D6)',
        ),
      );
    }

    final measured = entry['measured'];
    if (measured is num) {
      issues.add(
        AugmentationManifestIssue(
          path: '$path.measured',
          message:
              'must never be a bare number — a missing measurement is '
              'the literal "$_notMeasured", never numeric 0 (ADR 0525 D6), '
              'got $measured',
        ),
      );
    } else if (measured == _notMeasured) {
      if (status == 'accepted') {
        issues.add(
          AugmentationManifestIssue(
            path: '$path.status',
            message:
                'status is "accepted" but measured=="$_notMeasured" — '
                'ADR 0525 D6 forbids accepting an unmeasured transform',
          ),
        );
      }
    } else if (measured is Map<String, Object?>) {
      _validateMeasuredSplits(measured, status, path, issues);
    } else {
      issues.add(
        AugmentationManifestIssue(
          path: '$path.measured',
          message:
              'must be either the literal "$_notMeasured" or an object '
              'of measured splits',
        ),
      );
    }
  }
}

void _validateMeasuredSplits(
  Map<String, Object?> measured,
  Object? status,
  String path,
  List<AugmentationManifestIssue> issues,
) {
  final splits = <Map<String, Object?>>[
    for (final key in const ['unseenPlayerSplits', 'unseenDeviceSplits'])
      if (measured[key] is List)
        ...(measured[key]! as List).cast<Map<String, Object?>>(),
  ];
  if (splits.isEmpty) {
    issues.add(
      AugmentationManifestIssue(
        path: '$path.measured',
        message:
            'has a measured object but no unseenPlayerSplits/'
            'unseenDeviceSplits',
      ),
    );
    return;
  }

  var improves = false;
  var degradesBeyondError = false;
  for (final split in splits) {
    final baseline = split['baseline'];
    final treated = split['treated'];
    final delta = split['delta'];
    if (baseline is! num || treated is! num || delta is! num) {
      issues.add(
        AugmentationManifestIssue(
          path: '$path.measured',
          message: 'every split needs numeric baseline/treated/delta',
        ),
      );
      continue;
    }
    final expectedDelta = treated - baseline;
    if ((expectedDelta - delta).abs() > 1e-6) {
      issues.add(
        AugmentationManifestIssue(
          path: '$path.measured.${split['split']}.delta',
          message: 'must equal treated - baseline ($expectedDelta), got $delta',
        ),
      );
    }
    if (delta > 0) improves = true;
    final baselineErr = (split['baselineStdDev'] as num?)?.toDouble() ?? 0.0;
    final treatedErr = (split['treatedStdDev'] as num?)?.toDouble() ?? 0.0;
    if (delta < 0 && delta.abs() > (baselineErr + treatedErr)) {
      degradesBeyondError = true;
    }
  }

  if (status == 'accepted' && (!improves || degradesBeyondError)) {
    issues.add(
      AugmentationManifestIssue(
        path: '$path.status',
        message:
            'status is "accepted" but requires at least one improving '
            'split and no split degrading beyond its reported error bar '
            '(ADR 0525 D6)',
      ),
    );
  }
  if (status == 'rejected' && improves && !degradesBeyondError) {
    issues.add(
      AugmentationManifestIssue(
        path: '$path.status',
        message:
            'status is "rejected" but the measured splits show a '
            'clean improvement — should not be "rejected" (ADR 0525 D6)',
      ),
    );
  }
}

void _validateClassRatios(
  Map<String, Object?> doc,
  List<AugmentationManifestIssue> issues,
) {
  final classRatios = doc['classRatios'];
  if (classRatios is! Map<String, Object?>) {
    issues.add(
      const AugmentationManifestIssue(
        path: r'$.classRatios',
        message: 'missing required field: classRatios',
      ),
    );
    return;
  }
  for (final groupName in const ['direction', 'chord']) {
    final group = classRatios[groupName];
    if (group is! Map<String, Object?>) {
      issues.add(
        AugmentationManifestIssue(
          path: '\$.classRatios.$groupName',
          message: 'missing required group: $groupName',
        ),
      );
      continue;
    }
    for (final phase in const ['baseline', 'balanced']) {
      final ratios = group[phase];
      if (ratios is! Map<String, Object?> || ratios.isEmpty) {
        issues.add(
          AugmentationManifestIssue(
            path: '\$.classRatios.$groupName.$phase',
            message: 'missing required non-empty phase: $phase',
          ),
        );
        continue;
      }
      final total = ratios.values.whereType<num>().fold<double>(
        0.0,
        (sum, v) => sum + v.toDouble(),
      );
      if ((total - 1.0).abs() > 1e-6) {
        issues.add(
          AugmentationManifestIssue(
            path: '\$.classRatios.$groupName.$phase',
            message: 'ratios must sum to 1.0, got $total',
          ),
        );
      }
    }
  }
}

void _validatePitchShiftLimits(
  Map<String, Object?> doc,
  List<AugmentationManifestIssue> issues,
) {
  final limits = doc['pitchShiftLimits'];
  if (limits is! Map<String, Object?>) {
    issues.add(
      const AugmentationManifestIssue(
        path: r'$.pitchShiftLimits',
        message: 'missing required field: pitchShiftLimits',
      ),
    );
    return;
  }
  final pcm = limits['pcmVarispeedMaxSemitones'];
  if (pcm != 6) {
    issues.add(
      AugmentationManifestIssue(
        path: r'$.pitchShiftLimits.pcmVarispeedMaxSemitones',
        message: 'must be the literal 6 (ADR 0525 D3 ISMIR optimum), got $pcm',
      ),
    );
  }
  final cqt = limits['cqtChordTrackMaxSemitones'];
  if (cqt != 5) {
    issues.add(
      AugmentationManifestIssue(
        path: r'$.pitchShiftLimits.cqtChordTrackMaxSemitones',
        message:
            'must be the literal 5 (ml/chords/augment.py::'
            'augment_windows default max_semi — a DIFFERENT constraint from '
            'the PCM/varispeed limit, round brief R11), got $cqt',
      ),
    );
  }
}

void _validateBalancing(
  Map<String, Object?> doc,
  List<AugmentationManifestIssue> issues,
) {
  final balancing = doc['balancing'];
  if (balancing is! Map<String, Object?>) {
    issues.add(
      const AugmentationManifestIssue(
        path: r'$.balancing',
        message: 'missing required field: balancing',
      ),
    );
    return;
  }
  if (balancing['dropsRealData'] != false) {
    issues.add(
      AugmentationManifestIssue(
        path: r'$.balancing.dropsRealData',
        message:
            'must be exactly false — balancing may only weight/'
            'resample, never drop real data (ADR 0525 D8), got '
            '${balancing['dropsRealData']}',
      ),
    );
  }
  final method = balancing['method'];
  if (method is! String || method.isEmpty) {
    issues.add(
      const AugmentationManifestIssue(
        path: r'$.balancing.method',
        message: 'must be a non-empty string',
      ),
    );
  }
}
