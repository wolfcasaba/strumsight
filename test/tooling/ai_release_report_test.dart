// AI/ML release evidence aggregator gate (E12-R16, ADR 0477).
//
// Follows the `test/tooling/benchmark_budget_test.dart` (E12-R14) fixture
// pattern: `tool/release/build_ai_report.py` is exercised by shelling out to
// `python3` on a device-matrix / model-manifest / evidence-matrix / evidence
// fixture tree written to `Directory.systemTemp` at test run time and torn
// down in `tearDown` — the allowed-files list for this round does not
// include `test/fixtures/**`, so no fixture is committed. `python3` is the
// ONLY external binary this file is allowed to invoke (self-check group
// A9); there is no `skip:` branch anywhere.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixtureRoot;

  setUp(() {
    fixtureRoot = Directory.systemTemp.createTempSync(
      'strumsight_ai_release_report_',
    );
  });
  tearDown(() => fixtureRoot.deleteSync(recursive: true));

  String writeFile(String name, String content) {
    final file = File('${fixtureRoot.path}/$name');
    file.writeAsStringSync(content);
    return file.path;
  }

  String writeJson(String name, Map<String, Object?> content) =>
      writeFile(name, jsonEncode(content));

  String matrixYaml(List<Map<String, Object?>> capabilities) {
    final buffer = StringBuffer('capabilities:\n');
    for (final capability in capabilities) {
      buffer.writeln('  - id: ${capability['id']}');
      buffer.writeln('    ga_scope: ${capability['ga_scope']}');
    }
    return buffer.toString();
  }

  String manifestJson({
    List<Map<String, Object?>> models = const [],
    List<Map<String, Object?>> visionModels = const [],
  }) => jsonEncode(<String, Object?>{
    'models': models,
    'vision_models': visionModels,
  });

  String gateTable(List<List<String>> rows) {
    final buffer = StringBuffer();
    buffer.writeln('<!-- ai-quality-gates:begin -->');
    buffer.writeln(
      '| capability | metric | direction | model | evidence_path |',
    );
    buffer.writeln('|---|---|---|---|---|');
    for (final row in rows) {
      buffer.writeln('| ${row.join(' | ')} |');
    }
    buffer.writeln('<!-- ai-quality-gates:end -->');
    return buffer.toString();
  }

  Map<String, Object?> evidence({
    String corpusId = 'corpus-1',
    String buildSha = 'sha-1',
    String modelId = 'none',
    String modelVersion = 'none',
    num baselineValue = 0.800,
    num candidateValue = 0.7608,
  }) => <String, Object?>{
    'corpusId': corpusId,
    'buildSha': buildSha,
    'modelId': modelId,
    'modelVersion': modelVersion,
    'baselineValue': baselineValue,
    'candidateValue': candidateValue,
  };

  ProcessResult runReport({
    required String profile,
    required String scopeFile,
    required String matrixFile,
    required String manifestFile,
  }) => Process.runSync('python3', [
    'tool/release/build_ai_report.py',
    '--profile',
    profile,
    '--scope-file',
    scopeFile,
    '--matrix',
    matrixFile,
    '--model-manifest',
    manifestFile,
  ]);

  Map<String, Object?> decodeReport(ProcessResult result) =>
      jsonDecode(result.stdout as String) as Map<String, Object?>;

  String pythonEval(String expression) {
    final result = Process.runSync('python3', ['-c', 'print($expression)']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return (result.stdout as String).trim();
  }

  group('A1 — a ga_scope: true capability with missing/unreadable evidence '
      'blocks, and the capability shows "missing" in the output '
      '(ADR 0477 D2)', () {
    test('a non-existent evidence path is a non-zero exit', () {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'audio_analysis_core', 'ga_scope': true},
        ]),
      );
      final manifest = writeFile('manifest.json', manifestJson());
      final scope = writeFile(
        'scope.md',
        gateTable([
          [
            'audio_analysis_core',
            'chord_accuracy',
            'higherIsBetter',
            'none',
            '${fixtureRoot.path}/missing_evidence.json',
          ],
        ]),
      );

      final result = runReport(
        profile: 'development',
        scopeFile: scope,
        matrixFile: matrix,
        manifestFile: manifest,
      );

      expect(result.exitCode, isNot(0));
      final report = decodeReport(result);
      final capabilities = report['capabilities']! as List;
      final entry = capabilities.single as Map<String, Object?>;
      expect(entry['id'], 'audio_analysis_core');
      expect(entry['status'], 'missing');
      expect(entry['metrics'], isEmpty);
      expect(
        (report['findings']! as List).cast<String>(),
        anyElement(contains('audio_analysis_core/chord_accuracy')),
      );
    });

    test('an evidence file that is not valid JSON (e.g. prose Markdown) is '
        'the same "missing" outcome, never a crash', () {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'audio_analysis_core', 'ga_scope': true},
        ]),
      );
      final manifest = writeFile('manifest.json', manifestJson());
      final evidencePath = writeFile(
        'evidence.md',
        '# Not JSON\n\nThis is a prose report, not a structured document.\n',
      );
      final scope = writeFile(
        'scope.md',
        gateTable([
          [
            'audio_analysis_core',
            'chord_accuracy',
            'higherIsBetter',
            'none',
            evidencePath,
          ],
        ]),
      );

      final result = runReport(
        profile: 'development',
        scopeFile: scope,
        matrixFile: matrix,
        manifestFile: manifest,
      );

      expect(result.exitCode, isNot(0));
      final entry =
          (decodeReport(result)['capabilities']! as List).single
              as Map<String, Object?>;
      expect(entry['status'], 'missing');
    });
  });

  group('A2 — the report modelVersion must match assets/ml/model_manifest.'
      'json exactly; identity/version drift blocks (ADR 0477 D5, R3)', () {
    test('models[] filename/training_run.identifier mismatch blocks', () {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'cap', 'ga_scope': true},
        ]),
      );
      final manifest = writeFile(
        'manifest.json',
        manifestJson(
          models: [
            {
              'filename': 'chord_crnn.bin',
              'training_run': {'identifier': 'git:aaaa'},
            },
          ],
        ),
      );
      final evidencePath = writeJson(
        'evidence.json',
        evidence(modelId: 'chord_crnn.bin', modelVersion: 'git:different'),
      );
      final scope = writeFile(
        'scope.md',
        gateTable([
          ['cap', 'm1', 'higherIsBetter', 'model:chord_crnn.bin', evidencePath],
        ]),
      );

      final result = runReport(
        profile: 'development',
        scopeFile: scope,
        matrixFile: matrix,
        manifestFile: manifest,
      );

      expect(result.exitCode, isNot(0));
      expect(
        (decodeReport(result)['findings']! as List).cast<String>(),
        anyElement(contains('modelVersion')),
      );
    });

    test('vision_models[] model_id/version mismatch blocks', () {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'cap', 'ga_scope': true},
        ]),
      );
      final manifest = writeFile(
        'manifest.json',
        manifestJson(
          visionModels: [
            {'model_id': 'hand_landmarker', 'version': '1.0.0'},
          ],
        ),
      );
      final evidencePath = writeJson(
        'evidence.json',
        evidence(modelId: 'hand_landmarker', modelVersion: '0.9.0'),
      );
      final scope = writeFile(
        'scope.md',
        gateTable([
          [
            'cap',
            'm1',
            'higherIsBetter',
            'vision:hand_landmarker',
            evidencePath,
          ],
        ]),
      );

      final result = runReport(
        profile: 'development',
        scopeFile: scope,
        matrixFile: matrix,
        manifestFile: manifest,
      );

      expect(result.exitCode, isNot(0));
      expect(
        (decodeReport(result)['findings']! as List).cast<String>(),
        anyElement(contains('modelVersion')),
      );
    });

    test('modelId "none" on a row the gate table maps to a real model '
        'blocks — "none" is never a universal escape hatch', () {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'cap', 'ga_scope': true},
        ]),
      );
      final manifest = writeFile(
        'manifest.json',
        manifestJson(
          models: [
            {
              'filename': 'chord_crnn.bin',
              'training_run': {'identifier': 'git:aaaa'},
            },
          ],
        ),
      );
      final evidencePath = writeJson(
        'evidence.json',
        evidence(modelId: 'none', modelVersion: 'none'),
      );
      final scope = writeFile(
        'scope.md',
        gateTable([
          ['cap', 'm1', 'higherIsBetter', 'model:chord_crnn.bin', evidencePath],
        ]),
      );

      final result = runReport(
        profile: 'development',
        scopeFile: scope,
        matrixFile: matrix,
        manifestFile: manifest,
      );

      expect(result.exitCode, isNot(0));
      expect(
        (decodeReport(result)['findings']! as List).cast<String>(),
        anyElement(contains('modelId')),
      );
    });
  });

  group('A3 — ga_scope: false never blocks and shows "not_in_scope"; '
      'ga_scope comes only from the device matrix, never a baked-in list '
      '(ADR 0477 D1/D3)', () {
    test('a not_in_scope capability with missing evidence is a zero exit, '
        'shown as not_in_scope', () {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'ai_tutor', 'ga_scope': false},
        ]),
      );
      final manifest = writeFile('manifest.json', manifestJson());
      final scope = writeFile(
        'scope.md',
        gateTable([
          [
            'ai_tutor',
            'tutor_eval_pass_rate',
            'higherIsBetter',
            'none',
            '${fixtureRoot.path}/never_read.json',
          ],
        ]),
      );

      final result = runReport(
        profile: 'development',
        scopeFile: scope,
        matrixFile: matrix,
        manifestFile: manifest,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final entry =
          (decodeReport(result)['capabilities']! as List).single
              as Map<String, Object?>;
      expect(entry['status'], 'not_in_scope');
    });

    test('the exact SAME evidence-matrix input blocks once the fixture '
        'device matrix flips ga_scope to true for the same capability — '
        'proof there is no capability list baked into the Python source or '
        'the Markdown matrix', () {
      final manifest = writeFile('manifest.json', manifestJson());
      final scopeContent = gateTable([
        [
          'ai_tutor',
          'tutor_eval_pass_rate',
          'higherIsBetter',
          'none',
          '${fixtureRoot.path}/never_read.json',
        ],
      ]);
      final scope = writeFile('scope.md', scopeContent);

      final outOfScopeMatrix = writeFile(
        'matrix_out.yaml',
        matrixYaml([
          {'id': 'ai_tutor', 'ga_scope': false},
        ]),
      );
      final inScopeMatrix = writeFile(
        'matrix_in.yaml',
        matrixYaml([
          {'id': 'ai_tutor', 'ga_scope': true},
        ]),
      );

      final outOfScopeResult = runReport(
        profile: 'development',
        scopeFile: scope,
        matrixFile: outOfScopeMatrix,
        manifestFile: manifest,
      );
      final inScopeResult = runReport(
        profile: 'development',
        scopeFile: scope,
        matrixFile: inScopeMatrix,
        manifestFile: manifest,
      );

      expect(outOfScopeResult.exitCode, 0);
      expect(inScopeResult.exitCode, isNot(0));
    });
  });

  group('A4 — regression classification is imported from tool/compare_'
      'benchmarks.py, never redefined (ADR 0477 D4)', () {
    test('the source imports classify/WARN_THRESHOLD/FAIL_THRESHOLD from '
        'compare_benchmarks and contains neither a threshold literal nor '
        'its own "def classify"', () {
      final source = File('tool/release/build_ai_report.py').readAsStringSync();

      expect(source, contains('from compare_benchmarks import'));
      expect(source, contains('classify'));
      expect(source, contains('WARN_THRESHOLD'));
      expect(source, contains('FAIL_THRESHOLD'));
      expect(source, isNot(contains('def classify')));
      for (final literal in ['0.05', '0.10', '5.0', '10.0']) {
        expect(
          source,
          isNot(contains(literal)),
          reason: 'threshold literal "$literal" must not appear',
        );
      }
    });

    test('the report\'s top-level "thresholds" field carries the SAME '
        'warn/fail values tool/compare_benchmarks.py defines — read from '
        'that source at test time, never re-typed as a Dart literal, so '
        'the imported WARN_THRESHOLD/FAIL_THRESHOLD names are load-bearing '
        'and not merely present in the source (review E12-R16 MINOR-1)', () {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'ai_tutor', 'ga_scope': false},
        ]),
      );
      final manifest = writeFile('manifest.json', manifestJson());
      final scope = writeFile(
        'scope.md',
        gateTable([
          [
            'ai_tutor',
            'm1',
            'higherIsBetter',
            'none',
            '${fixtureRoot.path}/never_read.json',
          ],
        ]),
      );

      final result = runReport(
        profile: 'development',
        scopeFile: scope,
        matrixFile: matrix,
        manifestFile: manifest,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final thresholds =
          decodeReport(result)['thresholds']! as Map<String, Object?>;

      final sourced = Process.runSync('python3', [
        '-c',
        "import sys; sys.path.insert(0, 'tool'); "
            "from compare_benchmarks import WARN_THRESHOLD, FAIL_THRESHOLD; "
            "import json; "
            "print(json.dumps({'warn': WARN_THRESHOLD, 'fail': FAIL_THRESHOLD}))",
      ]);
      expect(sourced.exitCode, 0, reason: sourced.stderr.toString());
      final expected =
          jsonDecode(sourced.stdout as String) as Map<String, Object?>;

      expect(thresholds['warn'], expected['warn']);
      expect(thresholds['fail'], expected['fail']);
    });
  });

  group('A5 — every metric carries corpusId, buildSha, modelId and '
      'modelVersion; any missing field is a hard, non-zero-exit error '
      '(ADR 0477 D5)', () {
    test('the schema declares all four fields required on every metric', () {
      final schema =
          jsonDecode(
                File('tool/release/ai_report_schema.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      final metricDef =
          (schema['definitions']! as Map<String, Object?>)['metric']!
              as Map<String, Object?>;
      final required = (metricDef['required']! as List).cast<String>();
      for (final field in ['corpusId', 'buildSha', 'modelId', 'modelVersion']) {
        expect(required, contains(field));
      }
    });

    for (final field in ['corpusId', 'buildSha', 'modelId', 'modelVersion']) {
      test('a missing "$field" in the evidence document is a non-zero '
          'exit', () {
        final matrix = writeFile(
          'matrix.yaml',
          matrixYaml([
            {'id': 'cap', 'ga_scope': true},
          ]),
        );
        final manifest = writeFile('manifest.json', manifestJson());
        final evidenceJson = evidence()..remove(field);
        final evidencePath = writeJson('evidence.json', evidenceJson);
        final scope = writeFile(
          'scope.md',
          gateTable([
            ['cap', 'm1', 'higherIsBetter', 'none', evidencePath],
          ]),
        );

        final result = runReport(
          profile: 'development',
          scopeFile: scope,
          matrixFile: matrix,
          manifestFile: manifest,
        );

        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains(field));
      });
    }
  });

  group('A6 — --profile is a closed, provenance-only dictionary that never '
      'loosens or tightens a check (ADR 0477 D6)', () {
    test('development, lab and production are all accepted and echoed into '
        'the report "profile" field', () {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'ai_tutor', 'ga_scope': false},
        ]),
      );
      final manifest = writeFile('manifest.json', manifestJson());
      final scope = writeFile(
        'scope.md',
        gateTable([
          [
            'ai_tutor',
            'm1',
            'higherIsBetter',
            'none',
            '${fixtureRoot.path}/never_read.json',
          ],
        ]),
      );

      for (final profile in ['development', 'lab', 'production']) {
        final result = runReport(
          profile: profile,
          scopeFile: scope,
          matrixFile: matrix,
          manifestFile: manifest,
        );
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(decodeReport(result)['profile'], profile);
      }
    });

    test('an unknown profile value is a usage error, exit code 2', () {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'ai_tutor', 'ga_scope': false},
        ]),
      );
      final manifest = writeFile('manifest.json', manifestJson());
      final scope = writeFile(
        'scope.md',
        gateTable([
          [
            'ai_tutor',
            'm1',
            'higherIsBetter',
            'none',
            '${fixtureRoot.path}/never_read.json',
          ],
        ]),
      );

      final result = runReport(
        profile: 'staging',
        scopeFile: scope,
        matrixFile: matrix,
        manifestFile: manifest,
      );

      expect(result.exitCode, 2);
    });

    test('the SAME missing-evidence input produces the SAME non-zero exit '
        'code on all three profiles — a "development is lenient" weakening '
        'would break this', () {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'audio_analysis_core', 'ga_scope': true},
        ]),
      );
      final manifest = writeFile('manifest.json', manifestJson());
      final scope = writeFile(
        'scope.md',
        gateTable([
          [
            'audio_analysis_core',
            'chord_accuracy',
            'higherIsBetter',
            'none',
            '${fixtureRoot.path}/missing_evidence.json',
          ],
        ]),
      );

      final exitCodes = <int>{};
      for (final profile in ['development', 'lab', 'production']) {
        final result = runReport(
          profile: profile,
          scopeFile: scope,
          matrixFile: matrix,
          manifestFile: manifest,
        );
        exitCodes.add(result.exitCode);
      }
      expect(exitCodes, hasLength(1));
      expect(exitCodes.single, isNot(0));
    });
  });

  group('A7 — a gate-table capability unknown to the device matrix is a '
      'hard configuration error, never a silent skip (ADR 0477 D1)', () {
    test('a capability the device matrix does not name is exit code 2', () {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'audio_analysis_core', 'ga_scope': true},
        ]),
      );
      final manifest = writeFile('manifest.json', manifestJson());
      final scope = writeFile(
        'scope.md',
        gateTable([
          [
            'a_capability_the_device_matrix_never_heard_of',
            'm1',
            'higherIsBetter',
            'none',
            '${fixtureRoot.path}/never_read.json',
          ],
        ]),
      );

      final result = runReport(
        profile: 'development',
        scopeFile: scope,
        matrixFile: matrix,
        manifestFile: manifest,
      );

      expect(result.exitCode, 2);
      expect(
        result.stderr.toString(),
        contains('a_capability_the_device_matrix_never_heard_of'),
      );
    });
  });

  group('Pinned coverage — the two MEASURED, AI-evidence-bearing GA-scope '
      'capabilities (audio_analysis_core, live_and_tuner — round brief '
      '§0.0 R2) must stay present in the SHIPPED evidence matrix and '
      'SHIPPED device matrix, never a fixture copy; deleting a row is a '
      'cheaper way to go green than measuring, and nothing else catches '
      'that (review E12-R16 MAJOR-1)', () {
    const pinnedCapabilities = ['audio_analysis_core', 'live_and_tuner'];

    Set<String> gateTableCapabilities(String content) {
      if (!content.contains('<!-- ai-quality-gates:begin -->') ||
          !content.contains('<!-- ai-quality-gates:end -->')) {
        fail(
          'docs/release/ai-quality-gates.md is missing its machine-readable '
          'table markers (<!-- ai-quality-gates:begin/end -->)',
        );
      }
      final block = content
          .split('<!-- ai-quality-gates:begin -->')[1]
          .split('<!-- ai-quality-gates:end -->')[0];
      final rows = block
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.startsWith('|'))
          .skip(2); // header row, then the "|---|---|..." separator row
      return rows.map((line) => line.split('|')[1].trim()).toSet();
    }

    Map<String, bool> deviceMatrixGaScope(String content) {
      final matches = RegExp(
        r'-\s*id:\s*(\S+)\s*\n\s*ga_scope:\s*(true|false)',
      ).allMatches(content);
      return {
        for (final match in matches) match.group(1)!: match.group(2) == 'true',
      };
    }

    test('the shipped docs/release/ai-quality-gates.md gate table names '
        'both pinned capabilities — removing a row is the cheap way to '
        'make the gate pass by measuring nothing, not by measuring it', () {
      final content = File(
        'docs/release/ai-quality-gates.md',
      ).readAsStringSync();
      final capabilities = gateTableCapabilities(content);
      for (final capability in pinnedCapabilities) {
        expect(
          capabilities,
          contains(capability),
          reason:
              'docs/release/ai-quality-gates.md no longer has a gate-table '
              'row for "$capability" — deleting this row turns the release '
              'gate GREEN by making the capability disappear from the '
              'report entirely, instead of measuring it and turning it '
              'RED. Restore the row; do not edit this cell to pass.',
        );
      }
    });

    test('the shipped docs/testing/device-matrix.yaml still marks both '
        'pinned capabilities ga_scope: true — losing that silently drops '
        'their evidence requirement, so this must be a deliberate, '
        'reviewed change, not a silent one', () {
      final content = File(
        'docs/testing/device-matrix.yaml',
      ).readAsStringSync();
      final gaScope = deviceMatrixGaScope(content);
      for (final capability in pinnedCapabilities) {
        expect(
          gaScope[capability],
          isTrue,
          reason:
              'docs/testing/device-matrix.yaml no longer marks '
              '"$capability" ga_scope: true — if this GA-scope change is '
              'intended, update this pinned-coverage cell '
              '(test/tooling/ai_release_report_test.dart) deliberately; '
              'do not let AI-evidence coverage drop silently.',
        );
      }
    });
  });

  group('Threshold cell triple — the ADR 0474 thresholds inherited and only '
      'applied here (5% warn, 10% fail, both boundaries inclusive); inputs '
      'computed with python3, not hand-typed, per the round brief', () {
    ProcessResult runWithDelta(String candidate) {
      final matrix = writeFile(
        'matrix.yaml',
        matrixYaml([
          {'id': 'audio_analysis_core', 'ga_scope': true},
        ]),
      );
      final manifest = writeFile('manifest.json', manifestJson());
      final evidencePath = writeJson(
        'evidence.json',
        evidence(baselineValue: 0.800, candidateValue: double.parse(candidate)),
      );
      final scope = writeFile(
        'scope.md',
        gateTable([
          [
            'audio_analysis_core',
            'chord_accuracy',
            'higherIsBetter',
            'none',
            evidencePath,
          ],
        ]),
      );
      return runReport(
        profile: 'development',
        scopeFile: scope,
        matrixFile: matrix,
        manifestFile: manifest,
      );
    }

    test('4.9% regression (0.7608) is pass, exit 0', () {
      final candidate = pythonEval('0.800 * (1 - 0.049)');
      final result = runWithDelta(candidate);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final metric =
          ((decodeReport(result)['capabilities']! as List).single
                  as Map<String, Object?>)['metrics']!
              as List;
      expect((metric.single as Map<String, Object?>)['status'], 'pass');
    });

    test('5.0% regression (0.76), exactly on the boundary, is warn — not '
        'pass — and does not block', () {
      final candidate = pythonEval('0.800 * (1 - 0.050)');
      final result = runWithDelta(candidate);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final metric =
          ((decodeReport(result)['capabilities']! as List).single
                  as Map<String, Object?>)['metrics']!
              as List;
      expect((metric.single as Map<String, Object?>)['status'], 'warn');
    });

    test('10.0% regression (0.72), exactly on the boundary, is fail — '
        'not warn — and blocks with a non-zero exit', () {
      final candidate = pythonEval('0.800 - (0.800 * 0.100)');
      final result = runWithDelta(candidate);
      expect(result.exitCode, isNot(0));
      final metric =
          ((decodeReport(result)['capabilities']! as List).single
                  as Map<String, Object?>)['metrics']!
              as List;
      expect((metric.single as Map<String, Object?>)['status'], 'fail');
    });
  });

  group('A9 — this gate never relies on an unguaranteed or forbidden '
      'binary (benchmark_budget_test.dart L110 pattern)', () {
    test('every external process this file spawns — through any dart:io '
        'Process.run/.runSync/.start entry point — targets python3 only, '
        'never rg/grep/jq/gh/git', () {
      final source = File(
        'test/tooling/ai_release_report_test.dart',
      ).readAsStringSync();
      final executables = _processCallExecutable
          .allMatches(source)
          .map((match) => match.group(1)!)
          .toSet();
      expect(executables, isNotEmpty, reason: 'this file must call python3');
      expect(executables, {'python3'});
    });

    test('self-check: python3 is on PATH in this environment — if it is '
        'not, the calls above throw ProcessException and this whole file '
        'turns red, never a silent skip', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });
  });
}

// Built via adjacent string-literal concatenation so this constant's own
// definition text never spells out the executable-call pattern it searches
// for as one contiguous run of characters (the same construction
// `benchmark_budget_test.dart` uses, for the same reason — otherwise the A9
// self-scan above would match its own regex source).
final _processCallExecutable = RegExp(
  'Process'
  r'''\.(?:run|runSync|start)\(\s*['"]([^'"\n]+)['"]''',
);
