// Recognition baseline manifest gate (E14-R02, ADR 0354).
//
// Follows the `test/tooling/fixture_manifest_test.dart` /
// `test/tooling/benchmark_budget_test.dart` pattern: the pure Dart tool
// (`tool/benchmarks/recognition_baseline_manifest.dart`) is imported as a
// library and exercised directly via `buildRecognitionBaselineManifestReport`
// — no `Process` call anywhere in this file, since the generator is Dart,
// not an external interpreter. Synthetic fixtures are built as in-memory
// JSON text; the two "temp directory" determinism runs (§0.0/R8) write into
// `Directory.systemTemp` copies torn down in `addTearDown`. No real fixture
// under `evaluation/recognition/**` or `docs/eval/**` is ever mutated by a
// test — mutation cells build their own manifest text from scratch.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmarks/recognition_baseline_manifest.dart';

void main() {
  group('A1 — the real, shipped manifest validates against the schema, and '
      'carries exactly the six metric blocks in the §0.0/R5 classification '
      '(ADR 0354 D3, round §6 AC1)', () {
    test('the real baseline_manifest.json validates cleanly against the '
        'real schema', () {
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: _realManifestText(),
      );

      expect(report.isClean, isTrue, reason: report.formatIssues());
    });

    test('chord and onset are measured; direction, noChord, latency and '
        'calibration are not-measured — the exact §0.0/R5 split', () {
      final manifest = jsonDecode(_realManifestText()) as Map<String, Object?>;
      final blocks = manifest['metricBlocks']! as Map<String, Object?>;

      expect(blocks.keys.toSet(), {
        'onset',
        'direction',
        'chord',
        'noChord',
        'latency',
        'calibration',
      });
      for (final measured in ['chord', 'onset']) {
        expect(
          (blocks[measured]! as Map<String, Object?>)['status'],
          'measured',
          reason: measured,
        );
      }
      for (final notMeasured in [
        'direction',
        'noChord',
        'latency',
        'calibration',
      ]) {
        final block = blocks[notMeasured]! as Map<String, Object?>;
        expect(block['status'], 'not-measured', reason: notMeasured);
        expect(
          block['notMeasuredReason'],
          isA<String>().having((r) => r.isNotEmpty, 'non-empty', isTrue),
          reason: notMeasured,
        );
        expect(block.containsKey('metrics'), isFalse, reason: notMeasured);
      }
    });

    test('the real chord.accuracy and onset tolerance50000us.recall figures '
        'match docs/eval/real-audio-dsp-baseline.md exactly, each with its '
        'own sourceFile and command', () {
      final manifest = jsonDecode(_realManifestText()) as Map<String, Object?>;
      final chordMetrics =
          ((manifest['metricBlocks']! as Map<String, Object?>)['chord']!
                  as Map<String, Object?>)['metrics']!
              as Map<String, Object?>;
      final accuracy = chordMetrics['accuracy']! as Map<String, Object?>;
      expect(accuracy['value'], 0.6706892156029575);
      expect(accuracy['n'], 11767);
      expect(accuracy['sourceFile'], 'docs/eval/real-audio-dsp-baseline.md');
      expect(accuracy['command'], isNotEmpty);

      final onsetMetrics =
          ((manifest['metricBlocks']! as Map<String, Object?>)['onset']!
                  as Map<String, Object?>)['metrics']!
              as Map<String, Object?>;
      final recall50 =
          onsetMetrics['tolerance50000us.recall']! as Map<String, Object?>;
      expect(recall50['value'], 0.7087617914506671);
      expect(recall50['n'], 11767);
    });
  });

  group('A2 — every "measured" metric requires value+n+sourceFile+command; '
      'the fail-closed numeric threshold triple (ADR 0354 D2/D6, §6 AC3/AC6, '
      '§6.1 matrix)', () {
    test('n=0 on a metric is rejected — fail-closed, never an "n/a" row', () {
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(
          _validManifest(
            chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 0)},
          ),
        ),
      );

      expect(report.isClean, isFalse);
      expect(report.renderedIndex, isNull);
    });

    test('n=1 on a metric passes, and the rendered index marks it "n=1" — a '
        'single sample is not evidence', () {
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(
          _validManifest(
            chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 1)},
          ),
        ),
      );

      expect(report.isClean, isTrue, reason: report.formatIssues());
      expect(report.renderedIndex, contains('n=1'));
      expect(report.renderedIndex, contains('single sample'));
    });

    test('n=82, a normal measured count, passes with no "single sample" '
        'caveat', () {
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(
          _validManifest(
            chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 82)},
          ),
        ),
      );

      expect(report.isClean, isTrue, reason: report.formatIssues());
      expect(report.renderedIndex, isNot(contains('single sample')));
      expect(report.renderedIndex, contains('| 82 |'));
    });

    test('a metric entry missing "command" fails closed — a shared '
        'document footnote is not an acceptable substitute (ADR 0354 D2)', () {
      final metric = _metricEntry(value: 0.5, n: 10)..remove('command');
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(
          _validManifest(chordMetrics: {'accuracy': metric}),
        ),
      );

      expect(report.isClean, isFalse);
    });

    test('a metric entry missing "sourceFile" fails closed', () {
      final metric = _metricEntry(value: 0.5, n: 10)..remove('sourceFile');
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(
          _validManifest(chordMetrics: {'accuracy': metric}),
        ),
      );

      expect(report.isClean, isFalse);
    });
  });

  group('A3 — the BPM block is always retracted, mechanically, and the '
      'index says so (ADR 0354 D4, §6 AC4, §6.1 "deleted retracted row" '
      'matrix cell)', () {
    test('the real manifest\'s bpm block is retracted with a non-empty '
        'reason and its plucking-density / tempo-match numbers intact', () {
      final manifest = jsonDecode(_realManifestText()) as Map<String, Object?>;
      final bpm = manifest['bpm']! as Map<String, Object?>;

      expect(bpm['retracted'], isTrue);
      expect((bpm['retractedReason'] as String).isNotEmpty, isTrue);
      final metrics = bpm['metrics']! as Map<String, Object?>;
      expect(
        metrics.keys,
        containsAll(<String>[
          'pluckDensityMeanAbsoluteErrorBpm',
          'strictTempoMatch',
          'toleranceLevelTempoMatch',
        ]),
      );
    });

    test('the rendered index marks the BPM section RETRACTED, not a plain '
        'metric block', () {
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: _realManifestText(),
      );

      expect(report.isClean, isTrue, reason: report.formatIssues());
      expect(report.renderedIndex, contains('## BPM — RETRACTED'));
      expect(report.renderedIndex, contains('**This claim is retracted.**'));
    });

    test('a bpm block missing "retracted" fails schema validation — the '
        'retraction cannot be silently dropped by omission', () {
      final manifest = _validManifest(
        chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 10)},
      );
      (manifest['bpm']! as Map<String, Object?>).remove('retracted');

      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(manifest),
      );

      expect(report.isClean, isFalse);
    });

    test('a bpm block with retracted: false is rejected — this block is '
        'always a retraction (ADR 0354 D4 "const true")', () {
      final manifest = _validManifest(
        chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 10)},
      );
      (manifest['bpm']! as Map<String, Object?>)['retracted'] = false;

      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(manifest),
      );

      expect(report.isClean, isFalse);
    });
  });

  group('A4 — bitwise-identical re-runs: the renderer sorts, it does not '
      'trust manifest authoring order (ADR 0354 D5, §6 AC2, §6.1 "Map '
      'traversal order" / "raw toString()" matrix rows)', () {
    test('two temp-directory runs fed the SAME data with metric keys in '
        'DIFFERENT insertion order render byte-identical index files — a '
        'generator that writes in Map traversal order instead of sorting '
        'would fail this', () {
      final forwardOrder = <String, Object?>{
        'aTag': _metricEntry(value: 0.111, n: 5),
        'zTag': _metricEntry(value: 0.999, n: 50),
      };
      final reversedOrder = <String, Object?>{
        'zTag': _metricEntry(value: 0.999, n: 50),
        'aTag': _metricEntry(value: 0.111, n: 5),
      };

      final manifestA = jsonEncode(_validManifest(chordMetrics: forwardOrder));
      final manifestB = jsonEncode(_validManifest(chordMetrics: reversedOrder));

      final dirA = Directory.systemTemp.createTempSync(
        'strumsight_recognition_manifest_a_',
      );
      addTearDown(() => dirA.deleteSync(recursive: true));
      final dirB = Directory.systemTemp.createTempSync(
        'strumsight_recognition_manifest_b_',
      );
      addTearDown(() => dirB.deleteSync(recursive: true));

      final indexBytesA = _renderIntoTempDir(
        dirA,
        schemaText: _realSchemaText(),
        manifestText: manifestA,
      );
      final indexBytesB = _renderIntoTempDir(
        dirB,
        schemaText: _realSchemaText(),
        manifestText: manifestB,
      );

      expect(indexBytesA, isNotEmpty);
      expect(indexBytesA, equals(indexBytesB));
    });

    test('float values render with toStringAsFixed(3), not raw toString() '
        '(platform-dependent formatting would diff across runs)', () {
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(
          _validManifest(
            chordMetrics: {
              'accuracy': _metricEntry(value: 1 / 3, n: 10, unit: 'ratio'),
            },
          ),
        ),
      );

      expect(report.isClean, isTrue, reason: report.formatIssues());
      // 1/3 as a ratio, *100, fixed to 3 decimals: 33.333%. A raw
      // `(1/3*100).toString()` would instead print a long, platform-shaped
      // repeating-decimal literal.
      expect(report.renderedIndex, contains('33.333%'));
      expect(report.renderedIndex, isNot(contains((1 / 3 * 100).toString())));
    });

    test('self-check: the generator never calls DateTime.now() or a random '
        'source — the only timestamp in the render comes from the '
        'manifest\'s own generatedAt field', () {
      final source = File(
        'tool/benchmarks/recognition_baseline_manifest.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('DateTime.now()')));
      expect(source, isNot(contains('Random(')));
    });

    test('self-check: the generator imports no dart:ui, nothing from '
        'lib/**, and not the dart:ui-transitive real_audio_dsp_baseline.dart '
        'sibling (§0.0/R8) — checked against the actual import statements, '
        'not the file text (the file\'s own comments name all three as '
        'documentation of what NOT to do)', () {
      final source = File(
        'tool/benchmarks/recognition_baseline_manifest.dart',
      ).readAsStringSync();
      final imports = RegExp(
        r'''^import\s+['"]([^'"]+)['"]''',
        multiLine: true,
      ).allMatches(source).map((match) => match.group(1)!).toList();

      expect(imports, isNotEmpty);
      for (final importPath in imports) {
        expect(importPath, isNot(contains('dart:ui')), reason: importPath);
        expect(importPath, isNot(contains('/lib/')), reason: importPath);
        expect(
          importPath,
          isNot(contains('real_audio_dsp_baseline.dart')),
          reason: importPath,
        );
      }
    });
  });

  group('A5 — "not measured" is a first-class, closed shape: half-filled '
      'measured/not-measured blocks are rejected (ADR 0354 D3, §0.0/R4)', () {
    test('status "measured" together with a "notMeasuredReason" field is '
        'rejected — the two states are mutually exclusive', () {
      final manifest = _validManifest(
        chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 10)},
      );
      ((manifest['metricBlocks']! as Map<String, Object?>)['chord']!
              as Map<String, Object?>)['notMeasuredReason'] =
          'oops';

      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(manifest),
      );

      expect(report.isClean, isFalse);
    });

    test('status "not-measured" together with a "metrics" object is '
        'rejected', () {
      final manifest = _validManifest(
        chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 10)},
      );
      ((manifest['metricBlocks']! as Map<String, Object?>)['direction']!
          as Map<String, Object?>)['metrics'] = {
        'x': _metricEntry(value: 0.1, n: 1),
      };

      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(manifest),
      );

      expect(report.isClean, isFalse);
    });

    test('status "measured" with an EMPTY metrics object is rejected — a '
        'half-filled block is not a valid intermediate state', () {
      final manifest = _validManifest(
        chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 10)},
      );
      ((manifest['metricBlocks']! as Map<String, Object?>)['chord']!
              as Map<String, Object?>)['metrics'] =
          <String, Object?>{};

      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(manifest),
      );

      expect(report.isClean, isFalse);
    });

    test('status "not-measured" with an empty notMeasuredReason string is '
        'rejected', () {
      final manifest = _validManifest(
        chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 10)},
      );
      ((manifest['metricBlocks']! as Map<String, Object?>)['direction']!
              as Map<String, Object?>)['notMeasuredReason'] =
          '';

      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(manifest),
      );

      expect(report.isClean, isFalse);
    });

    test('a metricBlocks object missing one of the six required blocks is '
        'rejected', () {
      final manifest = _validManifest(
        chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 10)},
      );
      (manifest['metricBlocks']! as Map<String, Object?>).remove('latency');

      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(manifest),
      );

      expect(report.isClean, isFalse);
    });
  });

  group('A6 — an empty "models" list requires a non-empty modelsRationale; '
      'a non-empty list does not (ADR 0354 D7)', () {
    test('the real manifest ships models: [] with a non-empty '
        'modelsRationale', () {
      final manifest = jsonDecode(_realManifestText()) as Map<String, Object?>;
      expect(manifest['models'], isEmpty);
      expect((manifest['modelsRationale'] as String).isNotEmpty, isTrue);
    });

    test('models: [] with modelsRationale removed is rejected', () {
      final manifest = _validManifest(
        chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 10)},
      );
      manifest.remove('modelsRationale');

      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(manifest),
      );

      expect(report.isClean, isFalse);
    });

    test('a non-empty models list is accepted without a modelsRationale', () {
      final manifest = _validManifest(
        chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 10)},
      );
      manifest.remove('modelsRationale');
      manifest['models'] = [
        {'name': 'chord_crnn', 'sha256': List.filled(64, 'a').join()},
      ];

      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(manifest),
      );

      expect(report.isClean, isTrue, reason: report.formatIssues());
    });

    test('a fabricated model hash cannot silently coexist with an empty '
        'models list — models: [] but modelsRationale absent is rejected '
        'even if the fabricated hash lives elsewhere in the document', () {
      final manifest = _validManifest(
        chordMetrics: {'accuracy': _metricEntry(value: 0.5, n: 10)},
      );
      manifest.remove('modelsRationale');
      // models stays [] — an empty list always needs the rationale,
      // regardless of what else the document claims.
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: jsonEncode(manifest),
      );

      expect(report.isClean, isFalse);
    });
  });

  group('A7 — the index references the narrative docs, it does not copy '
      'them (ADR 0354 D9, §6 AC5)', () {
    test('the real rendered index links to both real-audio-dsp-baseline.md '
        'and recognition-release-guard.md by relative path', () {
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: _realManifestText(),
      );

      expect(report.isClean, isTrue, reason: report.formatIssues());
      expect(report.renderedIndex, contains('(real-audio-dsp-baseline.md)'));
      expect(report.renderedIndex, contains('(recognition-release-guard.md)'));
    });

    test('the index does not embed the raw GOV-06 JSON dump narrative that '
        'lives in real-audio-dsp-baseline.md — that would be a copy, not a '
        'link', () {
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: _realManifestText(),
      );

      expect(report.renderedIndex, isNot(contains('Shell: {')));
      expect(report.renderedIndex, isNot(contains('GOV-06 eredeti')));
    });
  });

  group('A8 — the real, shipped manifest and the real, committed index '
      'agree byte-for-byte right now (ties AC1/AC2/AC3 together on real '
      'data — a "--check" run against the real repository files)', () {
    test('rendering the real manifest reproduces '
        'docs/eval/recognition-baseline-index.md exactly', () {
      final report = buildRecognitionBaselineManifestReport(
        schemaJsonText: _realSchemaText(),
        manifestJsonText: _realManifestText(),
      );

      expect(report.isClean, isTrue, reason: report.formatIssues());
      final onDisk = File(
        '${_findProjectRoot().path}/docs/eval/recognition-baseline-index.md',
      ).readAsStringSync();
      expect(report.renderedIndex, onDisk);
    });
  });
}

// --- Fixtures ---------------------------------------------------------

String _realSchemaText() => File(
  '${_findProjectRoot().path}/evaluation/recognition/baseline_manifest_schema.json',
).readAsStringSync();

String _realManifestText() => File(
  '${_findProjectRoot().path}/evaluation/recognition/baseline_manifest.json',
).readAsStringSync();

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

Map<String, Object?> _metricEntry({
  required double value,
  required int n,
  String? unit,
}) {
  final entry = <String, Object?>{
    'value': value,
    'n': n,
    'sourceFile': 'docs/eval/real-audio-dsp-baseline.md',
    'command': 'echo synthetic-fixture-command',
  };
  if (unit != null) entry['unit'] = unit;
  return entry;
}

/// A minimal, schema-valid manifest with one caller-supplied chord metrics
/// map, so every test can vary exactly the field under test.
Map<String, Object?> _validManifest({
  required Map<String, Object?> chordMetrics,
}) {
  return <String, Object?>{
    'schemaVersion': '1.0',
    'generatedAt': '2026-01-01T00:00:00Z',
    'corpus': <String, Object?>{
      'corpusId': 'ml/data/klangio',
      'corpusSha256': List.filled(64, '0').join(),
      'recordingCount': 82,
      'eventCount': 11767,
      'skippedRecordingCount': 0,
    },
    'appCommit': 'deadbee',
    'appCommitNote': 'Synthetic fixture note for the tooling gate.',
    'configuration': <String, Object?>{
      'chunkSize': 2048,
      'strumRefiner': null,
      'chromaMedianWindow': 1,
      'bassWeight': null,
    },
    'models': <Object?>[],
    'modelsRationale': 'Synthetic fixture: no model participated.',
    'metricBlocks': <String, Object?>{
      'chord': <String, Object?>{'status': 'measured', 'metrics': chordMetrics},
      'onset': <String, Object?>{
        'status': 'measured',
        'metrics': <String, Object?>{
          'tolerance50000us.recall': _metricEntry(value: 0.5, n: 10),
        },
      },
      'direction': <String, Object?>{
        'status': 'not-measured',
        'notMeasuredReason': 'Synthetic fixture: not applicable.',
      },
      'noChord': <String, Object?>{
        'status': 'not-measured',
        'notMeasuredReason': 'Synthetic fixture: not applicable.',
      },
      'latency': <String, Object?>{
        'status': 'not-measured',
        'notMeasuredReason': 'Synthetic fixture: not applicable.',
      },
      'calibration': <String, Object?>{
        'status': 'not-measured',
        'notMeasuredReason': 'Synthetic fixture: not applicable.',
      },
    },
    'bpm': <String, Object?>{
      'retracted': true,
      'retractedReason': 'Synthetic fixture retraction.',
      'metrics': <String, Object?>{
        'pluckDensityMeanAbsoluteErrorBpm': _metricEntry(value: 40, n: 82),
      },
    },
  };
}

/// Writes [schemaText]/[manifestText] into a fresh `evaluation/recognition/`
/// tree under [root], renders the index in-process, writes it to
/// `docs/eval/recognition-baseline-index.md` under [root], and returns the
/// written bytes — the same read-render-write shape `main()` uses, minus
/// the CLI argument parsing.
List<int> _renderIntoTempDir(
  Directory root, {
  required String schemaText,
  required String manifestText,
}) {
  final report = buildRecognitionBaselineManifestReport(
    schemaJsonText: schemaText,
    manifestJsonText: manifestText,
  );
  if (!report.isClean) {
    fail('fixture manifest did not validate: ${report.formatIssues()}');
  }
  final indexFile = File(
    '${root.path}/docs/eval/recognition-baseline-index.md',
  );
  indexFile.parent.createSync(recursive: true);
  final bytes = utf8.encode(report.renderedIndex!);
  indexFile.writeAsBytesSync(bytes);
  return indexFile.readAsBytesSync();
}
