// Joint strum-prototype IO schema guard (E14-R18, ADR 0517).
//
// This round ships NO production Dart entry point (`lib/` and `tool/` are
// both in the forbidden zone, §5.5 forbids a shippable artifact) — so, as a
// deliberate, bounded exception to the "the cell measures the shipped entry
// point" pattern (ADR 0517 D8, precedent L631), the hand-written validator
// lives ENTIRELY in this test file rather than being imported from a library.
// A follow-up productization round moves it under `tool/` and imports it
// here (ADR 0517 D8) — that move is out of THIS round's allowed-files list.
//
// The validator has two layers, matching how `evaluate_prototype.py` is
// meant to be trusted:
//   1. generic JSON-Schema (draft-07 subset) structural validation against
//      the real evaluation/recognition/joint_io_schema.json, using the same
//      closed/restrictive keyword set as
//      tool/benchmarks/recognition_baseline_manifest.dart (ADR 0354 D8) —
//      an unknown schema keyword fails closed, never silently ignored;
//   2. cross-field SEMANTIC checks the JSON-Schema subset cannot express by
//      itself (ADR 0517 D1/D4/D6/D7): the lookahead's frame/ms pair actually
//      agree, the go/no-go verdict is recomputed from LITERAL Alpha-gate
//      thresholds rather than trusted from the document, every metric's
//      declared higherIsBetter matches its metric family's KNOWN direction,
//      and the legacy end-to-end direction row is unambiguously marked as a
//      derived ceiling rather than a measurement.
//
// No `Process` call anywhere in this file — this is a document-shape guard,
// not a script runner (the Python side is exercised manually, per the round
// brief §0.0/R3: it needs a TensorFlow interpreter `python3 -m pytest ml -q`
// cannot use).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('A1 — the real, shipped fixture validates cleanly against the real '
      'schema (sanity: the contract we ship is internally consistent)', () {
    test('the real joint_io_sample.json fixture validates cleanly against '
        'the real joint_io_schema.json', () {
      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: _realFixtureText(),
      );

      expect(report.isClean, isTrue, reason: report.formatIssues());
    });
  });

  group('A2 — schemaVersion is a fixed, typed contract; an unknown version '
      'is a typed error, never a silent default (ADR 0517 D3, round §6 '
      'AC4, §6.1 "unknown schema version -> default" row)', () {
    test('schemaVersion "2.0" is rejected', () {
      final doc = _fixture()..['schemaVersion'] = '2.0';
      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('schemaVersion'));
    });

    test('a missing schemaVersion field is rejected — never defaults to '
        '"1.0"', () {
      final doc = _fixture()..remove('schemaVersion');
      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
    });

    test('this is the round\'s mandated falsification cell (round §7.1): '
        'temporarily deleting the "const" keyword from schemaVersion\'s '
        'schema definition (simulating a validator that stopped enforcing '
        'the version) is documented in §10 as the RED state this test '
        'catches — this test itself stays green against the real schema '
        '(self-check, not a live mutation of the schema file)', () {
      final schema = jsonDecode(_realSchemaText()) as Map<String, Object?>;
      final properties = schema['properties']! as Map<String, Object?>;
      final schemaVersionSchema =
          properties['schemaVersion']! as Map<String, Object?>;
      expect(schemaVersionSchema['const'], '1.0');
    });
  });

  group('A3 — the lookahead number is present, numeric in both units, and '
      'internally consistent (ADR 0517 D1, round §6 AC3)', () {
    test('lookaheadMs must equal lookaheadFrames * hopMs', () {
      final doc = _fixture();
      (doc['lookahead']! as Map<String, Object?>)['lookaheadMs'] = 999;
      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('lookaheadMs'));
    });

    test('causal must be false whenever lookaheadFrames > 0', () {
      final doc = _fixture();
      (doc['lookahead']! as Map<String, Object?>)['causal'] = true;
      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('causal'));
    });

    test('causal must be true whenever lookaheadFrames == 0', () {
      final doc = _fixture();
      final lookahead = doc['lookahead']! as Map<String, Object?>;
      lookahead['lookaheadFrames'] = 0;
      lookahead['lookaheadMs'] = 0;
      lookahead['causal'] = false;
      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('causal'));
    });

    test('a lookahead block missing lookaheadFrames fails schema '
        'validation', () {
      final doc = _fixture();
      (doc['lookahead']! as Map<String, Object?>).remove('lookaheadFrames');
      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
    });
  });

  group('A4 — the go/no-go threshold triple is recomputed from LITERAL '
      'Alpha-gate constants, inclusive at the boundary (ADR 0517 D4, L637, '
      'round §6 AC5, §6.1 "exclusive threshold" row)', () {
    test('below/at/above are independently reproduced for BOTH metrics '
        'against their own literal threshold', () {
      for (final testCase in <(double, String)>[
        (0.81, 'below'),
        (0.82, 'at'),
        (0.83, 'above'),
      ]) {
        final (value, expectedComparison) = testCase;
        final doc = _fixture();
        (doc['metrics']! as Map<String, Object?>)
                .cast<
                  String,
                  Map<String, Object?>
                >()['prototypeOnsetF1At50ms']!['value'] =
            value;
        final verdict = doc['verdict']! as Map<String, Object?>;
        verdict['onsetF1Comparison'] = expectedComparison;
        // directionMacroF1 stays at the fixture's 0.5 ("below"); decision
        // must therefore stay "no-go" regardless of the onset side.
        verdict['decision'] = 'no-go';

        final report = validateJointIo(
          schemaJsonText: _realSchemaText(),
          documentJsonText: jsonEncode(doc),
        );

        expect(
          report.isClean,
          isTrue,
          reason:
              'value=$value expected=$expectedComparison: '
              '${report.formatIssues()}',
        );
      }
    });

    test('a document claiming "no-go" while BOTH metrics are AT or ABOVE '
        'their threshold is rejected — the exclusive-threshold bug class '
        '(the threshold is inclusive per ADR 0517 D4)', () {
      final doc = _fixture();
      final metrics = (doc['metrics']! as Map<String, Object?>)
          .cast<String, Map<String, Object?>>();
      metrics['prototypeOnsetF1At50ms']!['value'] = 0.82;
      metrics['prototypeDirectionMacroF1']!['value'] = 0.8;
      final verdict = doc['verdict']! as Map<String, Object?>;
      verdict['onsetF1Comparison'] = 'at';
      verdict['directionF1Comparison'] = 'at';
      verdict['decision'] = 'no-go'; // BUG: should be "go" (inclusive)

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('verdict.decision'));
    });

    test('a document claiming "go" while one metric is below its threshold '
        'is rejected', () {
      final doc = _fixture();
      final metrics = (doc['metrics']! as Map<String, Object?>)
          .cast<String, Map<String, Object?>>();
      metrics['prototypeOnsetF1At50ms']!['value'] = 0.9;
      metrics['prototypeDirectionMacroF1']!['value'] = 0.5; // below 0.80
      final verdict = doc['verdict']! as Map<String, Object?>;
      verdict['onsetF1Comparison'] = 'above';
      verdict['directionF1Comparison'] = 'below';
      verdict['decision'] = 'go'; // BUG

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('verdict.decision'));
    });

    test('a declared comparison that disagrees with the LITERAL recomputed '
        'comparison is rejected even when "decision" itself looks '
        'plausible', () {
      final doc = _fixture();
      final verdict = doc['verdict']! as Map<String, Object?>;
      // Fixture value is 0.5 ("below" 0.82) but the document claims "above".
      verdict['onsetF1Comparison'] = 'above';

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('onsetF1Comparison'));
    });

    test('a tampered literal threshold in the document itself (0.79 '
        'instead of 0.82) is rejected — the thresholds are fixed by the '
        'schema\'s "const", never authored per-run', () {
      final doc = _fixture();
      ((doc['verdict']! as Map<String, Object?>)['alphaThresholds']!
              as Map<String, Object?>)['onsetF1At50ms'] =
          0.79;

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
    });
  });

  group('A5 — every metric record carries the SAME direction its number is '
      'known to represent — the number and the sentence are measured '
      'together (ADR 0517 D7, L630, round §6 AC7)', () {
    test('flipping higherIsBetter on prototypeOnsetF1At50ms to false is '
        'rejected even though the field is independently well-formed '
        '(present, boolean-typed)', () {
      final doc = _fixture();
      ((doc['metrics']! as Map<String, Object?>)['prototypeOnsetF1At50ms']!
              as Map<String, Object?>)['definition']!
          as Map<String, Object?>;
      (((doc['metrics']! as Map<String, Object?>)['prototypeOnsetF1At50ms']!
                  as Map<String, Object?>)['definition']!
              as Map<String, Object?>)['higherIsBetter'] =
          false;

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
      expect(
        report.formatIssues(),
        contains('prototypeOnsetF1At50ms.definition.higherIsBetter'),
      );
    });

    test('flipping higherIsBetter on the latency metric to true is '
        'rejected — lower algorithmic latency is better, not higher', () {
      final doc = _fixture();
      (((doc['metrics']!
                      as Map<String, Object?>)['prototypeAlgorithmicLatencyMs']!
                  as Map<String, Object?>)['definition']!
              as Map<String, Object?>)['higherIsBetter'] =
          true;

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
      expect(
        report.formatIssues(),
        contains('prototypeAlgorithmicLatencyMs.definition.higherIsBetter'),
      );
    });

    test('flipping higherIsBetter on the legacy onset row is rejected the '
        'same way — the check applies to anchored legacy metrics too', () {
      final doc = _fixture();
      (((doc['metrics']! as Map<String, Object?>)['legacyOnsetF1At50ms']!
                  as Map<String, Object?>)['definition']!
              as Map<String, Object?>)['higherIsBetter'] =
          false;

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
    });
  });

  group('A6 — the legacy end-to-end direction row is a marked upper bound, '
      'never presented as a measurement (ADR 0517 D6, round §6 AC2, §6.1 '
      '"legacy direction reported as measured" row)', () {
    test('legacyDirectionF1UpperBound without a "bound" marker is rejected '
        '— that would let a not-measured legacy number pass as measured', () {
      final doc = _fixture();
      ((doc['metrics']! as Map<String, Object?>)['legacyDirectionF1UpperBound']!
              as Map<String, Object?>)
          .remove('bound');
      ((doc['metrics']! as Map<String, Object?>)['legacyDirectionF1UpperBound']!
              as Map<String, Object?>)
          .remove('derivation');

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('legacyDirectionF1UpperBound'));
    });

    test('legacyOnsetF1At50ms carrying a spurious "bound" marker is '
        'rejected — it is a real anchored measurement, not a derived '
        'ceiling', () {
      final doc = _fixture();
      ((doc['metrics']! as Map<String, Object?>)['legacyOnsetF1At50ms']!
              as Map<String, Object?>)['bound'] =
          'upper';
      ((doc['metrics']! as Map<String, Object?>)['legacyOnsetF1At50ms']!
              as Map<String, Object?>)['derivation'] =
          'fabricated';

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
      expect(report.formatIssues(), contains('legacyOnsetF1At50ms'));
    });

    test('a metric entry with "bound" but no "derivation" fails schema '
        'validation (oneOf: the pairing is mandatory)', () {
      final doc = _fixture();
      ((doc['metrics']! as Map<String, Object?>)['legacyDirectionF1UpperBound']!
              as Map<String, Object?>)
          .remove('derivation');

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
    });
  });

  group('A7 — corpus and leakage invariants are fixed truths a document '
      'either has, or does not exist to report otherwise (ADR 0517 D2/D6)', () {
    test('matchesBaselineManifest: false fails schema validation — a '
        'document that exists always carries this as true', () {
      final doc = _fixture();
      (doc['corpus']! as Map<String, Object?>)['matchesBaselineManifest'] =
          false;

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
    });

    test('leakageCheckPassed: false fails schema validation — a document '
        'that exists always carries this as true', () {
      final doc = _fixture();
      (doc['splitStrategy']! as Map<String, Object?>)['leakageCheckPassed'] =
          false;

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
    });

    test('corpusSha256 not matching the 64-hex-digit shape is rejected', () {
      final doc = _fixture();
      (doc['corpus']! as Map<String, Object?>)['corpusSha256'] = 'not-a-hash';

      final report = validateJointIo(
        schemaJsonText: _realSchemaText(),
        documentJsonText: jsonEncode(doc),
      );

      expect(report.isClean, isFalse);
    });
  });

  group('A8 — an unrecognized schema keyword fails closed instead of being '
      'silently ignored (ADR 0517 D8, ADR 0354 D8 precedent)', () {
    test('adding "maxLength": 3 to corpusId\'s schema — a keyword this '
        'hand-written validator does not implement — is rejected, even '
        'though the real fixture\'s corpusId would otherwise validate '
        'cleanly', () {
      final schema = jsonDecode(_realSchemaText()) as Map<String, Object?>;
      final definitions = schema['definitions']! as Map<String, Object?>;
      final corpusSchema = definitions['corpus']! as Map<String, Object?>;
      final properties = corpusSchema['properties']! as Map<String, Object?>;
      final corpusIdSchema = properties['corpusId']! as Map<String, Object?>;
      corpusIdSchema['maxLength'] = 3;

      final report = validateJointIo(
        schemaJsonText: jsonEncode(schema),
        documentJsonText: _realFixtureText(),
      );

      expect(report.isClean, isFalse);
      expect(
        report.formatIssues(),
        contains('unknown/unsupported keyword "maxLength"'),
      );
    });
  });
}

// --- Fixtures -----------------------------------------------------------

String _realSchemaText() => File(
  '${_findProjectRoot().path}/evaluation/recognition/joint_io_schema.json',
).readAsStringSync();

String _realFixtureText() => File(
  '${_findProjectRoot().path}/evaluation/recognition/fixtures/joint_io_sample.json',
).readAsStringSync();

/// A fresh, mutable copy of the real fixture document for each test — never
/// shared, so one test's mutation can never leak into another.
Map<String, Object?> _fixture() =>
    jsonDecode(_realFixtureText()) as Map<String, Object?>;

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

// --- Report types ---------------------------------------------------------

final class JointIoIssue {
  const JointIoIssue({required this.path, required this.message});

  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

final class JointIoReport {
  JointIoReport(List<JointIoIssue> issues) : issues = List.unmodifiable(issues);

  final List<JointIoIssue> issues;

  bool get isClean => issues.isEmpty;

  String formatIssues() {
    if (isClean) return 'Joint IO document OK.';
    final buffer = StringBuffer('Joint IO document check failed.');
    for (final issue in issues) {
      buffer
        ..writeln()
        ..write('- $issue');
    }
    return buffer.toString();
  }
}

/// Validates [documentJsonText] against [schemaJsonText] (generic JSON
/// Schema draft-07 subset) and, if that passes, against the ADR 0517
/// cross-field semantic rules the schema subset cannot itself express.
JointIoReport validateJointIo({
  required String schemaJsonText,
  required String documentJsonText,
}) {
  final issues = <JointIoIssue>[];

  Object? schema;
  try {
    schema = jsonDecode(schemaJsonText);
  } on FormatException catch (error) {
    issues.add(JointIoIssue(path: '<schema>', message: 'invalid JSON: $error'));
  }

  Object? document;
  try {
    document = jsonDecode(documentJsonText);
  } on FormatException catch (error) {
    issues.add(
      JointIoIssue(path: '<document>', message: 'invalid JSON: $error'),
    );
  }

  if (schema is! Map<String, Object?> || document is! Map<String, Object?>) {
    if (schema is! Map<String, Object?>) {
      issues.add(
        const JointIoIssue(
          path: '<schema>',
          message: 'schema root must be a JSON object',
        ),
      );
    }
    if (document is! Map<String, Object?>) {
      issues.add(
        const JointIoIssue(
          path: '<document>',
          message: 'document root must be a JSON object',
        ),
      );
    }
    return JointIoReport(issues);
  }

  issues.addAll(_validate(document, schema, schema, r'$'));
  if (issues.isNotEmpty) return JointIoReport(issues);

  issues.addAll(_validateSemantics(document));
  return JointIoReport(issues);
}

// --- Hand-written JSON Schema (draft-07 subset) validator ------------------
//
// Kept intentionally identical in spirit to
// tool/benchmarks/recognition_baseline_manifest.dart's validator (ADR 0354
// D8) but trimmed to exactly the keyword set evaluation/recognition/
// joint_io_schema.json actually uses — this schema has no arrays, so
// `items`/`minItems`/`maxItems`/`minProperties` are deliberately absent from
// the restrictive set (their absence is itself a fail-closed choice: if a
// future schema edit ever adds one, this validator rejects it as unknown
// rather than silently no-op'ing on it).

const _restrictiveSchemaKeywords = <String>{
  'type',
  'required',
  'additionalProperties',
  'properties',
  'const',
  'enum',
  'oneOf',
  'not',
  r'$ref',
  'pattern',
  'minimum',
  'minLength',
};

const _documentationSchemaKeywords = <String>{
  r'$schema',
  r'$id',
  'title',
  'description',
  'definitions',
};

List<JointIoIssue> _validate(
  Object? instance,
  Map<String, Object?> schema,
  Map<String, Object?> rootSchema,
  String path,
) {
  final resolved = _resolveRef(schema, rootSchema);
  final issues = <JointIoIssue>[];

  for (final key in resolved.keys) {
    if (!_restrictiveSchemaKeywords.contains(key) &&
        !_documentationSchemaKeywords.contains(key)) {
      issues.add(
        JointIoIssue(
          path: path,
          message:
              'schema declares unknown/unsupported keyword "$key" — '
              'fail-closed rather than silently ignored (ADR 0517 D8)',
        ),
      );
    }
  }

  if (resolved.containsKey('const')) {
    final constValue = resolved['const'];
    if (!_deepEquals(instance, constValue)) {
      issues.add(
        JointIoIssue(
          path: path,
          message:
              'must equal ${jsonEncode(constValue)}, got '
              '${jsonEncode(instance)}',
        ),
      );
      return issues;
    }
  }

  final enumValues = resolved['enum'];
  if (enumValues is List) {
    final matchesEnum = enumValues.any((value) => _deepEquals(instance, value));
    if (!matchesEnum) {
      issues.add(
        JointIoIssue(
          path: path,
          message: 'must be one of $enumValues, got ${jsonEncode(instance)}',
        ),
      );
      return issues;
    }
  }

  final type = resolved['type'];
  if (type != null && !_matchesType(instance, type)) {
    issues.add(
      JointIoIssue(
        path: path,
        message: 'must be of type $type, got ${_typeNameOf(instance)}',
      ),
    );
    return issues;
  }

  final pattern = resolved['pattern'];
  if (pattern is String && instance is String) {
    if (!RegExp(pattern).hasMatch(instance)) {
      issues.add(
        JointIoIssue(path: path, message: 'must match pattern $pattern'),
      );
    }
  }

  final minLength = resolved['minLength'];
  if (minLength is int && instance is String && instance.length < minLength) {
    issues.add(
      JointIoIssue(
        path: path,
        message: 'must be at least $minLength character(s)',
      ),
    );
  }

  final minimum = resolved['minimum'];
  if (minimum is num && instance is num && instance < minimum) {
    issues.add(JointIoIssue(path: path, message: 'must be >= $minimum'));
  }

  if (instance is Map<String, Object?>) {
    final required = resolved['required'];
    if (required is List) {
      for (final key in required) {
        if (key is String && !instance.containsKey(key)) {
          issues.add(
            JointIoIssue(
              path: path,
              message: 'missing required property "$key"',
            ),
          );
        }
      }
    }

    final properties = resolved['properties'];
    final propertySchemas = properties is Map<String, Object?>
        ? properties
        : const <String, Object?>{};
    final additional = resolved['additionalProperties'];

    for (final entry in instance.entries) {
      final key = entry.key;
      final propertySchema = propertySchemas[key];
      if (propertySchema is Map<String, Object?>) {
        issues.addAll(
          _validate(entry.value, propertySchema, rootSchema, '$path.$key'),
        );
      } else if (additional == false) {
        issues.add(
          JointIoIssue(
            path: '$path.$key',
            message:
                'unexpected property (not declared, '
                'additionalProperties: false)',
          ),
        );
      } else if (additional is Map<String, Object?>) {
        issues.addAll(
          _validate(entry.value, additional, rootSchema, '$path.$key'),
        );
      }
      // additional == true, or the keyword is absent: no constraint.
    }
  }

  final oneOf = resolved['oneOf'];
  if (oneOf is List) {
    final branchResults = <List<JointIoIssue>>[
      for (final branch in oneOf)
        if (branch is Map<String, Object?>)
          _validate(instance, branch, rootSchema, path),
    ];
    final matching = branchResults.where((result) => result.isEmpty).length;
    if (matching != 1) {
      issues.add(
        JointIoIssue(
          path: path,
          message:
              'must match exactly one alternative (matched $matching of '
              '${branchResults.length})',
        ),
      );
    }
  }

  final not = resolved['not'];
  if (not is Map<String, Object?>) {
    final forbidden = _validate(instance, not, rootSchema, path);
    if (forbidden.isEmpty) {
      issues.add(
        JointIoIssue(path: path, message: 'must not match the forbidden shape'),
      );
    }
  }

  return issues;
}

Map<String, Object?> _resolveRef(
  Map<String, Object?> schema,
  Map<String, Object?> rootSchema,
) {
  final ref = schema[r'$ref'];
  if (ref is! String) return schema;
  if (!ref.startsWith('#/')) {
    throw StateError(
      'unsupported \$ref (only local #/... pointers are supported): $ref',
    );
  }
  Object? cursor = rootSchema;
  for (final segment in ref.substring(2).split('/')) {
    if (cursor is Map<String, Object?>) {
      cursor = cursor[segment];
    } else {
      cursor = null;
    }
  }
  if (cursor is! Map<String, Object?>) {
    throw StateError('\$ref could not be resolved: $ref');
  }
  return cursor;
}

bool _matchesType(Object? instance, Object? type) {
  bool matchesOne(String candidate) {
    switch (candidate) {
      case 'object':
        return instance is Map;
      case 'string':
        return instance is String;
      case 'number':
        return instance is num;
      case 'integer':
        return instance is int ||
            (instance is double && instance == instance.roundToDouble());
      case 'boolean':
        return instance is bool;
      case 'null':
        return instance == null;
      default:
        return false;
    }
  }

  if (type is String) return matchesOne(type);
  if (type is List) {
    return type.any(
      (candidate) => candidate is String && matchesOne(candidate),
    );
  }
  return false;
}

String _typeNameOf(Object? instance) {
  if (instance == null) return 'null';
  if (instance is Map) return 'object';
  if (instance is List) return 'array';
  if (instance is String) return 'string';
  if (instance is bool) return 'boolean';
  if (instance is num) return 'number';
  return instance.runtimeType.toString();
}

bool _deepEquals(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!_deepEquals(a[index], b[index])) return false;
    }
    return true;
  }
  return a == b;
}

// --- Cross-field semantic checks (ADR 0517 D1/D4/D6/D7) --------------------
//
// Everything in this section is a rule the JSON-Schema draft-07 subset above
// cannot express by itself (it can check a field's own shape, never "this
// field's value must agree with a computation over three OTHER fields").
// Only runs once generic schema validation is already clean, so these
// checks can assume the shapes they read are actually present.

/// The known, hard-coded direction of improvement for every named metric —
/// independent of whatever `definition.higherIsBetter` a document declares.
/// A document that disagrees with this table is wrong about ITS OWN metric,
/// not about some external fact (ADR 0517 D7, L630): the classic bug class
/// is a metric's `value` being measured correctly while its `definition`
/// sentence silently drifts (or is copy-pasted from the wrong metric).
const _expectedHigherIsBetter = <String, bool>{
  'prototypeOnsetF1At50ms': true,
  'prototypeDirectionMacroF1': true,
  'prototypeAlgorithmicLatencyMs': false,
  'legacyOnsetF1At50ms': true,
  'legacyDirectionF1UpperBound': true,
};

/// Chapter 14 §7.2 Strum Alpha gate literals (docs/sdd/14-chapter-14-
/// recognition-ui-recovery.md) — LITERAL doubles, never computed by
/// arithmetic (ADR 0517 D4, L637): `repr(0.80) == '0.8'` and
/// `0.80 >= 0.80 -> True` are both safe under IEEE-754 double comparison
/// precisely because these are literals, not the result of a division or
/// running average.
const _onsetAlphaThreshold = 0.82;
const _directionAlphaThreshold = 0.8;

List<JointIoIssue> _validateSemantics(Map<String, Object?> document) {
  final issues = <JointIoIssue>[];

  final lookahead = document['lookahead']! as Map<String, Object?>;
  final preFrames = lookahead['preFrames'];
  final lookaheadFrames = lookahead['lookaheadFrames'];
  final hopMs = lookahead['hopMs'];
  final lookaheadMs = lookahead['lookaheadMs'];
  final causal = lookahead['causal'];
  if (lookaheadFrames is int && hopMs is num && lookaheadMs is num) {
    final expectedMs = lookaheadFrames * hopMs;
    if (expectedMs != lookaheadMs) {
      issues.add(
        JointIoIssue(
          path: r'$.lookahead.lookaheadMs',
          message:
              'must equal lookaheadFrames * hopMs = $expectedMs '
              '(ADR 0517 D1: the report and the schema carry the SAME '
              'number in both units) — got $lookaheadMs',
        ),
      );
    }
  }
  if (lookaheadFrames is int && causal is bool) {
    final expectedCausal = lookaheadFrames == 0;
    if (causal != expectedCausal) {
      issues.add(
        JointIoIssue(
          path: r'$.lookahead.causal',
          message:
              'must be $expectedCausal when lookaheadFrames=$lookaheadFrames '
              '— got $causal',
        ),
      );
    }
  }
  // preFrames is read only to keep the variable referenced for documentation
  // purposes — it carries no cross-field constraint of its own beyond the
  // schema's own `minimum: 0`.
  preFrames;

  final metrics = document['metrics']! as Map<String, Object?>;
  for (final entry in _expectedHigherIsBetter.entries) {
    final metric = metrics[entry.key];
    if (metric is! Map<String, Object?>) continue;
    final definition = metric['definition'];
    if (definition is! Map<String, Object?>) continue;
    final declared = definition['higherIsBetter'];
    if (declared != entry.value) {
      issues.add(
        JointIoIssue(
          path: '\$.metrics.${entry.key}.definition.higherIsBetter',
          message:
              'must be ${entry.value} for this metric (ADR 0517 D7) — got '
              '$declared, which contradicts this metric\'s known direction '
              'of improvement even though the field is independently '
              'well-formed (present, boolean-typed)',
        ),
      );
    }
  }

  final legacyDirection =
      metrics['legacyDirectionF1UpperBound'] as Map<String, Object?>?;
  if (legacyDirection != null && legacyDirection['bound'] != 'upper') {
    issues.add(
      const JointIoIssue(
        path: r'$.metrics.legacyDirectionF1UpperBound.bound',
        message:
            'must be "upper" — a legacy end-to-end direction number is '
            'never a direct measurement on this corpus (ADR 0517 D6); '
            'without this marker a not-measured number could pass as '
            'measured',
      ),
    );
  }
  final legacyOnset = metrics['legacyOnsetF1At50ms'] as Map<String, Object?>?;
  if (legacyOnset != null && legacyOnset.containsKey('bound')) {
    issues.add(
      const JointIoIssue(
        path: r'$.metrics.legacyOnsetF1At50ms.bound',
        message:
            'must not be present — this is a real anchored measurement '
            '(ADR 0354 baseline_manifest.json), not a derived ceiling',
      ),
    );
  }

  final verdict = document['verdict']! as Map<String, Object?>;
  final alphaThresholds = verdict['alphaThresholds']! as Map<String, Object?>;
  if (alphaThresholds['onsetF1At50ms'] != _onsetAlphaThreshold) {
    issues.add(
      JointIoIssue(
        path: r'$.verdict.alphaThresholds.onsetF1At50ms',
        message:
            'must equal the literal Chapter 14 Alpha gate '
            '$_onsetAlphaThreshold — got ${alphaThresholds['onsetF1At50ms']}',
      ),
    );
  }
  if (alphaThresholds['directionMacroF1'] != _directionAlphaThreshold) {
    issues.add(
      JointIoIssue(
        path: r'$.verdict.alphaThresholds.directionMacroF1',
        message:
            'must equal the literal Chapter 14 Alpha gate '
            '$_directionAlphaThreshold — got '
            '${alphaThresholds['directionMacroF1']}',
      ),
    );
  }

  final onsetValue =
      (metrics['prototypeOnsetF1At50ms']! as Map<String, Object?>)['value'];
  final directionValue =
      (metrics['prototypeDirectionMacroF1']! as Map<String, Object?>)['value'];
  final declaredOnsetComparison = verdict['onsetF1Comparison'];
  final declaredDirectionComparison = verdict['directionF1Comparison'];

  if (onsetValue is num) {
    final expected = _compareToThreshold(onsetValue, _onsetAlphaThreshold);
    if (declaredOnsetComparison != expected) {
      issues.add(
        JointIoIssue(
          path: r'$.verdict.onsetF1Comparison',
          message:
              'must be "$expected" for value $onsetValue against the '
              'literal threshold $_onsetAlphaThreshold (ADR 0517 D4) — got '
              '"$declaredOnsetComparison"',
        ),
      );
    }
  }
  if (directionValue is num) {
    final expected = _compareToThreshold(
      directionValue,
      _directionAlphaThreshold,
    );
    if (declaredDirectionComparison != expected) {
      issues.add(
        JointIoIssue(
          path: r'$.verdict.directionF1Comparison',
          message:
              'must be "$expected" for value $directionValue against the '
              'literal threshold $_directionAlphaThreshold (ADR 0517 D4) — '
              'got "$declaredDirectionComparison"',
        ),
      );
    }
  }

  if (declaredOnsetComparison is String &&
      declaredDirectionComparison is String) {
    final bothMeetOrExceed =
        (declaredOnsetComparison == 'at' ||
            declaredOnsetComparison == 'above') &&
        (declaredDirectionComparison == 'at' ||
            declaredDirectionComparison == 'above');
    final expectedDecision = bothMeetOrExceed ? 'go' : 'no-go';
    if (verdict['decision'] != expectedDecision) {
      issues.add(
        JointIoIssue(
          path: r'$.verdict.decision',
          message:
              'must be "$expectedDecision" (ADR 0517 D4: the threshold is '
              'inclusive, and BOTH metrics must meet or exceed it — '
              '"below" on either metric, including a near-miss, is '
              'no-go) — got "${verdict['decision']}"',
        ),
      );
    }
  }

  return issues;
}

String _compareToThreshold(num value, num threshold) {
  if (value < threshold) return 'below';
  if (value == threshold) return 'at';
  return 'above';
}
