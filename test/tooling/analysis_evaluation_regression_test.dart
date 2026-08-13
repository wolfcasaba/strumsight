/// Test-side regression gate for the Audio Analysis evaluation baseline
/// (E06-R29, ADR 0249 §Döntés 5-6). The CI-side workflow step is out of
/// scope for this round (H-GATEGUARD, `docs/rounds/e06-r29-…md` §5.1) — this
/// is its merge-time-equivalent, run via `tools/round-gate.sh`.
///
/// Baseline numbers are the ones recorded in
/// `docs/baseline/epic-06-analysis-evaluation.md`, produced by an actual run
/// of `tool/audio_analysis_evaluate.dart` against
/// `evaluation/analysis/fixtures/ci_manifest.json` — never hand-typed
/// targets.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/data/evaluation/evaluation_manifest_parser.dart';
import 'package:strumsight/features/audio_analysis/data/evaluation/evaluation_runner.dart';

// docs/baseline/epic-06-analysis-evaluation.md — overall block.
const double _baselineOnsetF1 = 0.9166666666666666;
const double _baselineChordSegmentAccuracy = 0.9375;
const double _baselineTimestampMaeMs = 3.977272727272727;
const double _baselineBpmErrorPercent = 0.7651515151515151;

// ADR 0249 §Döntés 5.
const double _f1RegressionToleranceAbsolute = 0.02;
const double _chordRegressionToleranceAbsolute = 0.02;
const double _relativeRegressionTolerance = 0.10;

final class RegressionVerdict {
  const RegressionVerdict({required this.passed, required this.failures});

  final bool passed;
  final List<String> failures;
}

/// The test-side equivalent of the future CI regression step: green unless
/// a metric regressed past its ADR 0249 tolerance. Improvement never fails.
RegressionVerdict evaluateRegression({
  required double onsetF1,
  required double chordSegmentAccuracy,
  required double timestampMaeMs,
  required double bpmErrorPercent,
}) {
  final failures = <String>[];

  if (_baselineOnsetF1 - onsetF1 > _f1RegressionToleranceAbsolute) {
    failures.add(
      'onset F1 regressed by more than 2pp '
      '(baseline $_baselineOnsetF1, got $onsetF1)',
    );
  }
  if (_baselineChordSegmentAccuracy - chordSegmentAccuracy >
      _chordRegressionToleranceAbsolute) {
    failures.add(
      'chord segment accuracy regressed by more than 2pp '
      '(baseline $_baselineChordSegmentAccuracy, got $chordSegmentAccuracy)',
    );
  }
  if (_relativeWorseningRatio(timestampMaeMs, _baselineTimestampMaeMs) >
      _relativeRegressionTolerance) {
    failures.add(
      'timestamp MAE regressed by more than 10% '
      '(baseline ${_baselineTimestampMaeMs}ms, got ${timestampMaeMs}ms)',
    );
  }
  if (_relativeWorseningRatio(bpmErrorPercent, _baselineBpmErrorPercent) >
      _relativeRegressionTolerance) {
    failures.add(
      'BPM error regressed by more than 10% '
      '(baseline $_baselineBpmErrorPercent%, got $bpmErrorPercent%)',
    );
  }

  return RegressionVerdict(passed: failures.isEmpty, failures: failures);
}

/// How much worse [current] is than [baseline] as a fraction of [baseline]
/// (negative or zero means [current] is no worse — an improvement never
/// fails the gate).
double _relativeWorseningRatio(double current, double baseline) {
  if (baseline <= 0) return current > 0 ? double.infinity : 0;
  return (current - baseline) / baseline;
}

void main() {
  group('regression gate — four cells', () {
    test('(a) exactly matching the baseline is green', () {
      final verdict = evaluateRegression(
        onsetF1: _baselineOnsetF1,
        chordSegmentAccuracy: _baselineChordSegmentAccuracy,
        timestampMaeMs: _baselineTimestampMaeMs,
        bpmErrorPercent: _baselineBpmErrorPercent,
      );
      expect(verdict.passed, isTrue, reason: verdict.failures.join('; '));
    });

    test('(b) a 2.1 percentage-point onset F1 regression is red', () {
      final verdict = evaluateRegression(
        onsetF1: _baselineOnsetF1 - 0.021,
        chordSegmentAccuracy: _baselineChordSegmentAccuracy,
        timestampMaeMs: _baselineTimestampMaeMs,
        bpmErrorPercent: _baselineBpmErrorPercent,
      );
      expect(verdict.passed, isFalse);
      expect(
        verdict.failures.any((f) => f.contains('onset F1')),
        isTrue,
        reason: verdict.failures.join('; '),
      );
    });

    test('(c) a 1.9 percentage-point onset F1 regression is green', () {
      final verdict = evaluateRegression(
        onsetF1: _baselineOnsetF1 - 0.019,
        chordSegmentAccuracy: _baselineChordSegmentAccuracy,
        timestampMaeMs: _baselineTimestampMaeMs,
        bpmErrorPercent: _baselineBpmErrorPercent,
      );
      expect(verdict.passed, isTrue, reason: verdict.failures.join('; '));
    });

    test('(d) an 11% BPM-error regression is red', () {
      final verdict = evaluateRegression(
        onsetF1: _baselineOnsetF1,
        chordSegmentAccuracy: _baselineChordSegmentAccuracy,
        timestampMaeMs: _baselineTimestampMaeMs,
        bpmErrorPercent: _baselineBpmErrorPercent * 1.11,
      );
      expect(verdict.passed, isFalse);
      expect(
        verdict.failures.any((f) => f.contains('BPM error')),
        isTrue,
        reason: verdict.failures.join('; '),
      );
    });

    test('improvement on every metric never fails the gate', () {
      final verdict = evaluateRegression(
        onsetF1: 1.0,
        chordSegmentAccuracy: 1.0,
        timestampMaeMs: 0,
        bpmErrorPercent: 0,
      );
      expect(verdict.passed, isTrue, reason: verdict.failures.join('; '));
    });
  });

  test('the current ci_manifest.json run passes its own regression gate '
      '(the baseline document was produced from this exact fixture)', () async {
    const parser = EvaluationManifestParser();
    const runner = EvaluationRunner();
    final manifest = parser.parseJsonString(
      await File(
        'evaluation/analysis/fixtures/ci_manifest.json',
      ).readAsString(),
    );
    final report = runner.run(manifest);
    final verdict = evaluateRegression(
      onsetF1: report.overall.onset.f1!,
      chordSegmentAccuracy: report.overall.chordSegmentAccuracy!,
      timestampMaeMs: report.overall.timestampMaeMs!,
      bpmErrorPercent: report.overall.bpmErrorPercent!,
    );
    expect(verdict.passed, isTrue, reason: verdict.failures.join('; '));
  });

  test(
    'the evaluation report JSON contains no absolute filesystem path',
    () async {
      const parser = EvaluationManifestParser();
      const runner = EvaluationRunner();
      final manifest = parser.parseJsonString(
        await File(
          'evaluation/analysis/fixtures/ci_manifest.json',
        ).readAsString(),
      );
      final json = runner.run(manifest).toDeterministicJson();
      expect(json, isNot(contains('/home/')));
      expect(json, isNot(contains(RegExp(r'[A-Za-z]:\\'))));
      // Sanity: it is real, well-formed JSON, not an accidental empty string.
      expect(jsonDecode(json), isA<Map<String, Object?>>());
    },
  );

  test('no binary audio file is part of this round\'s change', () async {
    final result = await Process.run('git', ['diff', '--stat', 'HEAD']);
    final stagedResult = await Process.run('git', [
      'diff',
      '--stat',
      '--cached',
      'HEAD',
    ]);
    const audioExtensions = ['.wav', '.mp3', '.m4a'];
    for (final output in [
      result.stdout as String,
      stagedResult.stdout as String,
    ]) {
      for (final line in const LineSplitter().convert(output)) {
        for (final extension in audioExtensions) {
          expect(
            line.contains(extension),
            isFalse,
            reason: 'binary audio file detected in diff: $line',
          );
        }
      }
    }
  });
}
