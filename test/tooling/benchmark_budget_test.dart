// Performance budget harness gate (E12-R14, ADR 0474).
//
// Follows the `test/tooling/device_matrix_test.dart` (E12-R13, PR #503) and
// `test/tooling/release_manifest_test.dart` (ADR 0447) pattern: the pure
// Dart schema (`tool/benchmarks/benchmark_record.dart`) is imported and
// exercised directly, while the Python comparator
// (`tool/compare_benchmarks.py`) is exercised by shelling out to `python3`
// on fixture files written to `Directory.systemTemp` at test run time and
// torn down in `addTearDown` — the allowed-files list for this round does
// not include `test/fixtures/**`, so no fixture is committed. `python3` is
// the ONLY external binary this file is allowed to invoke (L110); there is
// no skip branch anywhere (D9) — group A9 proves it self-referentially, the
// same self-defending pattern `device_matrix_test.dart` group A8 uses.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmarks/benchmark_record.dart';

void main() {
  group('A1 — the record schema parses, and build/device metadata are '
      'mandatory (ADR 0474 D1)', () {
    Map<String, Object?> validRecord({
      Map<String, Object?> overrides = const {},
    }) => <String, Object?>{
      'schemaVersion': 1,
      'metric': 'analysis_cache_miss_latency',
      'value': 30589,
      'unit': 'us',
      'sampleCount': 1,
      'kind': 'measured',
      'direction': 'lowerIsBetter',
      'source': 'docs/baseline/epic-06-analysis-performance.md:10',
      'buildSha': 'd325d60',
      'deviceId': 'ci_host',
      'timestamp': '2026-08-13T00:00:00Z',
      ...overrides,
    };

    test('a fully-populated record parses and round-trips every field', () {
      final record = BenchmarkRecord.fromJson(validRecord());
      expect(record.metric, 'analysis_cache_miss_latency');
      expect(record.value, 30589.0);
      expect(record.kind, 'measured');
      expect(record.direction, 'lowerIsBetter');
      expect(record.deviceId, 'ci_host');
      expect(record.buildSha, 'd325d60');
      expect(record.toJson()['metric'], 'analysis_cache_miss_latency');
    });

    test('a missing buildSha is a parse failure, not a defaulted value', () {
      final json = validRecord()..remove('buildSha');
      expect(
        () => BenchmarkRecord.fromJson(json),
        throwsA(isA<BenchmarkRecordFormatException>()),
      );
    });

    test('a missing deviceId is a parse failure, not "unknown-device"', () {
      final json = validRecord()..remove('deviceId');
      expect(
        () => BenchmarkRecord.fromJson(json),
        throwsA(isA<BenchmarkRecordFormatException>()),
      );
    });

    test('a deviceId outside the closed dictionary is rejected — inventing '
        'a device name is forbidden (ADR 0474 D2)', () {
      expect(
        () => BenchmarkRecord.fromJson(
          validRecord(overrides: {'deviceId': 'oneplus_12'}),
        ),
        throwsA(isA<BenchmarkRecordFormatException>()),
      );
    });

    test('every real device-matrix id plus ci_host is accepted', () {
      for (final deviceId in kBenchmarkRecordDeviceIds) {
        expect(
          BenchmarkRecord.fromJson(
            validRecord(overrides: {'deviceId': deviceId}),
          ).deviceId,
          deviceId,
        );
      }
    });

    test('an unknown kind is rejected', () {
      expect(
        () => BenchmarkRecord.fromJson(
          validRecord(overrides: {'kind': 'estimated'}),
        ),
        throwsA(isA<BenchmarkRecordFormatException>()),
      );
    });

    test('an unknown direction is rejected', () {
      expect(
        () => BenchmarkRecord.fromJson(
          validRecord(overrides: {'direction': 'sideways'}),
        ),
        throwsA(isA<BenchmarkRecordFormatException>()),
      );
    });

    test('an absolute POSIX source path is rejected (ADR 0447-style '
        'machine-path ban)', () {
      expect(
        () => BenchmarkRecord.fromJson(
          validRecord(overrides: {'source': '/home/ubuntu/tree/foo.md:1'}),
        ),
        throwsA(isA<BenchmarkRecordFormatException>()),
      );
    });

    test('an absolute Windows source path is rejected', () {
      expect(
        () => BenchmarkRecord.fromJson(
          validRecord(overrides: {'source': r'C:\tree\foo.md:1'}),
        ),
        throwsA(isA<BenchmarkRecordFormatException>()),
      );
    });

    test('a document with no "records" array is rejected', () {
      expect(
        () => parseBenchmarkRecords(jsonEncode(<String, Object?>{})),
        throwsA(isA<BenchmarkRecordFormatException>()),
      );
    });

    test('parseBenchmarkRecords parses a full document of one record', () {
      final records = parseBenchmarkRecords(
        jsonEncode(<String, Object?>{
          'records': [validRecord()],
        }),
      );
      expect(records, hasLength(1));
      expect(records.single.metric, 'analysis_cache_miss_latency');
    });
  });

  group('A4 — docs/performance/baseline.json parses in full and every '
      'entry cites a source file that actually exists (ADR 0474 D4)', () {
    late List<BenchmarkRecord> records;

    setUpAll(() {
      records = parseBenchmarkRecords(
        File('docs/performance/baseline.json').readAsStringSync(),
      );
    });

    test('the real baseline.json parses without throwing and is non-empty', () {
      expect(records, isNotEmpty);
    });

    test('every record\'s source references an existing repository file', () {
      for (final record in records) {
        final sourcePath = record.source.split(':').first;
        expect(
          File(sourcePath).existsSync(),
          isTrue,
          reason: '${record.metric} cites missing source "$sourcePath"',
        );
      }
    });

    test('every record carries a non-empty buildSha and a closed-dictionary '
        'deviceId (already enforced by fromJson, re-asserted on the real '
        'file so a future edit cannot silently reintroduce a gap)', () {
      for (final record in records) {
        expect(record.buildSha, isNotEmpty, reason: record.metric);
        expect(
          kBenchmarkRecordDeviceIds,
          contains(record.deviceId),
          reason: record.metric,
        );
      }
    });

    test('at least one measured, one upperBound, one derivedContract and '
        'one target entry exist — the four ADR 0474 D3 classes are all '
        'represented, not flattened into one', () {
      final kinds = records.map((r) => r.kind).toSet();
      expect(kinds, {'measured', 'upperBound', 'derivedContract', 'target'});
    });

    test('no record sourced from the epic-04 upperBound document ("< 0.1 '
        'ms" style) is classified "measured" — that specific weakening is '
        'the ADR 0474 D3 forbidden move', () {
      for (final record in records) {
        if (record.source.startsWith('docs/baseline/epic-04-performance.md')) {
          expect(record.kind, 'upperBound', reason: record.metric);
        }
      }
    });

    test('every target-kind entry has sampleCount 0 — it documents a '
        'threshold, not a measurement that was actually taken', () {
      for (final record in records) {
        if (record.kind == 'target') {
          expect(record.sampleCount, 0, reason: record.metric);
        }
      }
    });
  });

  group('compare_benchmarks.py fixture harness', () {
    late Directory fixtureRoot;

    setUp(() {
      fixtureRoot = Directory.systemTemp.createTempSync(
        'strumsight_benchmark_budget_',
      );
    });
    tearDown(() => fixtureRoot.deleteSync(recursive: true));

    Map<String, Object?> record({
      required String metric,
      required num value,
      String kind = 'measured',
      String direction = 'lowerIsBetter',
      String unit = 'us',
      int sampleCount = 1,
      String source = 'docs/baseline/epic-06-analysis-performance.md:10',
      String buildSha = 'd325d60',
      String deviceId = 'ci_host',
      String timestamp = '2026-08-13T00:00:00Z',
    }) => <String, Object?>{
      'schemaVersion': 1,
      'metric': metric,
      'value': value,
      'unit': unit,
      'sampleCount': sampleCount,
      'kind': kind,
      'direction': direction,
      'source': source,
      'buildSha': buildSha,
      'deviceId': deviceId,
      'timestamp': timestamp,
    };

    String writeDocument(String name, List<Map<String, Object?>> records) {
      final file = File('${fixtureRoot.path}/$name.json');
      file.writeAsStringSync(jsonEncode(<String, Object?>{'records': records}));
      return file.path;
    }

    ProcessResult runCompare(String baselinePath, String candidatePath) =>
        Process.runSync('python3', [
          'tool/compare_benchmarks.py',
          '--baseline',
          baselinePath,
          '--candidate',
          candidatePath,
        ]);

    group('A2 — metadata-less input is a non-zero exit, never a silently '
        'accepted comparison (ADR 0474 D1)', () {
      test('a candidate record missing deviceId fails closed', () {
        final baseline = writeDocument('baseline', [
          record(metric: 'm1', value: 100),
        ]);
        final candidateJson = record(metric: 'm1', value: 101)
          ..remove('deviceId');
        final candidate = writeDocument('candidate', [candidateJson]);

        final result = runCompare(baseline, candidate);
        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains('deviceId'));
      });

      test('a baseline record missing buildSha fails closed', () {
        final baselineJson = record(metric: 'm1', value: 100)
          ..remove('buildSha');
        final baseline = writeDocument('baseline', [baselineJson]);
        final candidate = writeDocument('candidate', [
          record(metric: 'm1', value: 101),
        ]);

        final result = runCompare(baseline, candidate);
        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains('buildSha'));
      });
    });

    group('A3 — a measured metric missing from the candidate is "unknown" '
        'and a non-zero exit, never dropped from the summary silently '
        '(ADR 0474 D5)', () {
      test('the missing metric is named "unknown" in the output', () {
        final baseline = writeDocument('baseline', [
          record(metric: 'analysis_cache_miss_latency', value: 30589),
        ]);
        final candidate = writeDocument('candidate', [
          record(metric: 'an_unrelated_metric', value: 1),
        ]);

        final result = runCompare(baseline, candidate);
        expect(result.exitCode, isNot(0));
        expect(
          result.stdout.toString(),
          contains('analysis_cache_miss_latency: status=unknown'),
        );
      });
    });

    group(
      'A5 — the lowerIsBetter threshold cell triple decides pass/warn/'
      'fail on the exact ADR 0474 D6 literals, both boundaries inclusive',
      () {
        final baseline = <String, Object?>{
          'metric': 'm1',
          'value': 200.0,
          'direction': 'lowerIsBetter',
        };

        test('4.9% regression (209.8) is pass', () {
          final baselinePath = writeDocument('baseline', [
            record(metric: baseline['metric']! as String, value: 200.0),
          ]);
          final candidatePath = writeDocument('candidate', [
            record(metric: baseline['metric']! as String, value: 209.8),
          ]);
          final result = runCompare(baselinePath, candidatePath);
          expect(result.exitCode, 0, reason: result.stderr.toString());
          expect(result.stdout.toString(), contains('m1: status=pass'));
        });

        test('5.0% regression (210.0), exactly on the boundary, is warn — '
            'not pass', () {
          final baselinePath = writeDocument('baseline', [
            record(metric: 'm1', value: 200.0),
          ]);
          final candidatePath = writeDocument('candidate', [
            record(metric: 'm1', value: 210.0),
          ]);
          final result = runCompare(baselinePath, candidatePath);
          expect(result.stdout.toString(), contains('m1: status=warn'));
        });

        test('10.0% regression (220.0), exactly on the boundary, is fail — '
            'not warn — and the exit code is non-zero', () {
          final baselinePath = writeDocument('baseline', [
            record(metric: 'm1', value: 200.0),
          ]);
          final candidatePath = writeDocument('candidate', [
            record(metric: 'm1', value: 220.0),
          ]);
          final result = runCompare(baselinePath, candidatePath);
          expect(result.exitCode, isNot(0));
          expect(result.stdout.toString(), contains('m1: status=fail'));
        });
      },
    );

    group('A7 — direction is per-metric with no default (ADR 0474 D7); the '
        'higherIsBetter threshold cell triple is the mirror image of A5', () {
      test('4.9% regression (28.53 vs baseline 30.0) is pass', () {
        final baselinePath = writeDocument('baseline', [
          record(
            metric: 'fps1',
            value: 30.0,
            direction: 'higherIsBetter',
            unit: 'fps',
          ),
        ]);
        final candidatePath = writeDocument('candidate', [
          record(
            metric: 'fps1',
            value: 28.53,
            direction: 'higherIsBetter',
            unit: 'fps',
          ),
        ]);
        final result = runCompare(baselinePath, candidatePath);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout.toString(), contains('fps1: status=pass'));
      });

      test('5.0% regression (28.5), exactly on the boundary, is warn — not '
          'pass', () {
        final baselinePath = writeDocument('baseline', [
          record(
            metric: 'fps1',
            value: 30.0,
            direction: 'higherIsBetter',
            unit: 'fps',
          ),
        ]);
        final candidatePath = writeDocument('candidate', [
          record(
            metric: 'fps1',
            value: 28.5,
            direction: 'higherIsBetter',
            unit: 'fps',
          ),
        ]);
        final result = runCompare(baselinePath, candidatePath);
        expect(result.stdout.toString(), contains('fps1: status=warn'));
      });

      test('10.0% regression (27.0), exactly on the boundary, is fail — '
          'not warn — and the exit code is non-zero', () {
        final baselinePath = writeDocument('baseline', [
          record(
            metric: 'fps1',
            value: 30.0,
            direction: 'higherIsBetter',
            unit: 'fps',
          ),
        ]);
        final candidatePath = writeDocument('candidate', [
          record(
            metric: 'fps1',
            value: 27.0,
            direction: 'higherIsBetter',
            unit: 'fps',
          ),
        ]);
        final result = runCompare(baselinePath, candidatePath);
        expect(result.exitCode, isNot(0));
        expect(result.stdout.toString(), contains('fps1: status=fail'));
      });

      test('a direction-blind ("always bigger delta = worse") comparator '
          'would report this higherIsBetter IMPROVEMENT (fps rising from '
          '30 to 40) as a regression; the real comparator must not', () {
        final baselinePath = writeDocument('baseline', [
          record(
            metric: 'fps1',
            value: 30.0,
            direction: 'higherIsBetter',
            unit: 'fps',
          ),
        ]);
        final candidatePath = writeDocument('candidate', [
          record(
            metric: 'fps1',
            value: 40.0,
            direction: 'higherIsBetter',
            unit: 'fps',
          ),
        ]);
        final result = runCompare(baselinePath, candidatePath);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout.toString(), contains('fps1: status=pass'));
      });

      test('a record with no "direction" field at all fails closed — it '
          'must never silently fall back to lowerIsBetter', () {
        final baselineJson = record(
          metric: 'fps1',
          value: 30.0,
          direction: 'higherIsBetter',
          unit: 'fps',
        )..remove('direction');
        final baselinePath = writeDocument('baseline', [baselineJson]);
        final candidatePath = writeDocument('candidate', [
          record(
            metric: 'fps1',
            value: 27.0,
            direction: 'higherIsBetter',
            unit: 'fps',
          ),
        ]);
        final result = runCompare(baselinePath, candidatePath);
        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains('direction'));
      });
    });

    group('A8 — only kind: "measured" records are ever compared (ADR 0474 '
        'D3); an upperBound entry never gates the run, however large the '
        'apparent delta', () {
      test('an upperBound metric with a wildly different candidate value '
          'produces no status line and does not block the exit', () {
        final baselinePath = writeDocument('baseline', [
          record(
            metric: 'ub1',
            value: 0.1,
            kind: 'upperBound',
            unit: 'ms',
            source: 'docs/baseline/epic-04-performance.md:27',
          ),
        ]);
        final candidatePath = writeDocument('candidate', [
          record(metric: 'ub1', value: 1000.0, kind: 'upperBound', unit: 'ms'),
        ]);
        final result = runCompare(baselinePath, candidatePath);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout.toString(), isNot(contains('ub1')));
      });

      test('a mixed document compares only the measured metric and ignores '
          'the derivedContract and target metrics alongside it', () {
        final baselinePath = writeDocument('baseline', [
          record(metric: 'measured1', value: 100),
          record(
            metric: 'contract1',
            value: 17,
            kind: 'derivedContract',
            unit: 'ms',
          ),
          record(
            metric: 'target1',
            value: 15,
            kind: 'target',
            direction: 'higherIsBetter',
            unit: 'fps',
            sampleCount: 0,
          ),
        ]);
        final candidatePath = writeDocument('candidate', [
          record(metric: 'measured1', value: 101),
          record(
            metric: 'contract1',
            value: 999,
            kind: 'derivedContract',
            unit: 'ms',
          ),
          record(
            metric: 'target1',
            value: 1,
            kind: 'target',
            direction: 'higherIsBetter',
            unit: 'fps',
            sampleCount: 0,
          ),
        ]);
        final result = runCompare(baselinePath, candidatePath);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout.toString(), contains('measured1: status=pass'));
        expect(result.stdout.toString(), isNot(contains('contract1')));
        expect(result.stdout.toString(), isNot(contains('target1')));
      });
    });

    group('A6 — the round-brief §7 self-comparison command runs clean', () {
      test('comparing docs/performance/baseline.json against itself is a '
          'zero exit with every measured metric passing', () {
        final result = Process.runSync('python3', [
          'tool/compare_benchmarks.py',
          '--baseline',
          'docs/performance/baseline.json',
          '--candidate',
          'docs/performance/baseline.json',
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout.toString(), isNot(contains('status=fail')));
        expect(result.stdout.toString(), isNot(contains('status=unknown')));
      });
    });
  });

  // No skip path anywhere in this file: if python3 is missing, every
  // `Process.runSync('python3', ...)` call above throws `ProcessException`
  // the first time a test reaches it, failing that test — exactly the
  // "PIROS, not skip" contract the self-check below measures directly.
  group('A9 — this gate never relies on an unguaranteed or forbidden '
      'binary (L110, L527)', () {
    test('every external process this file spawns — through any dart:io '
        'Process.run/.runSync/.start entry point — targets python3 only, '
        'never rg/grep/jq/gh/git', () {
      final source = File(
        'test/tooling/benchmark_budget_test.dart',
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
// for as one contiguous run of characters — the same construction
// `device_matrix_test.dart` uses, for the same reason (otherwise the A9
// self-scan above would match its own regex source).
final _processCallExecutable = RegExp(
  'Process'
  r'''\.(?:run|runSync|start)\(\s*['"]([^'"\n]+)['"]''',
);
