/// Recognition dashboard report + fail-closed release gate CLI (E14-R09,
/// ADR 0511).
///
/// Usage:
///   dart run tool/recognition_report.dart
///   dart run tool/recognition_report.dart --manifest PATH
///   dart run tool/recognition_report.dart --thresholds PATH
///   dart run tool/recognition_report.dart --format json|markdown|html
///
/// Defaults to the small, synthetic CI fixture
/// (`evaluation/recognition/fixtures/ci_manifest.json`) and the shipped v1
/// threshold file (`evaluation/recognition/recognition_release_gate.json`).
/// Prints the requested rendering of the single `RecognitionDashboardReport`
/// (ADR 0511 D5) to stdout and nothing else — the same manifest, thresholds
/// and code always produce byte-identical output (D7). The process exit
/// code reflects the release-gate verdict: `0` when it passes, `3` when it
/// fails closed (missing/below-threshold metric) — never `0` on a failing
/// gate. Parse and I/O failures are reported on stderr with a distinct
/// non-zero exit code.
library;

import 'dart:io';

import 'package:strumsight/features/live/data/evaluation/recognition_evaluation_runner.dart';
import 'package:strumsight/features/live/data/evaluation/recognition_report_renderer.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_metrics.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_release_gate.dart';

const _defaultManifestPath = 'evaluation/recognition/fixtures/ci_manifest.json';
const _defaultThresholdsPath =
    'evaluation/recognition/recognition_release_gate.json';
const _supportedFormats = <String>{'json', 'markdown', 'html'};

void main(List<String> arguments) async {
  var manifestPath = _defaultManifestPath;
  var thresholdsPath = _defaultThresholdsPath;
  var format = 'json';

  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--manifest' when i + 1 < arguments.length:
        manifestPath = arguments[++i];
      case '--thresholds' when i + 1 < arguments.length:
        thresholdsPath = arguments[++i];
      case '--format' when i + 1 < arguments.length:
        format = arguments[++i];
      case '--help':
        stdout.writeln(
          'Usage: dart run tool/recognition_report.dart '
          '[--manifest <path>] [--thresholds <path>] '
          '[--format json|markdown|html]',
        );
        return;
    }
  }

  if (!_supportedFormats.contains(format)) {
    stderr.writeln(
      'Unknown --format "$format" (expected one of '
      '${_supportedFormats.join(', ')})',
    );
    exitCode = 2;
    return;
  }

  final manifestFile = File(manifestPath);
  if (!await manifestFile.exists()) {
    stderr.writeln('Manifest not found: $manifestPath');
    exitCode = 2;
    return;
  }
  final thresholdsFile = File(thresholdsPath);
  if (!await thresholdsFile.exists()) {
    stderr.writeln('Threshold file not found: $thresholdsPath');
    exitCode = 2;
    return;
  }

  const runner = RecognitionEvaluationRunner();
  const gate = RecognitionReleaseGate();
  const rendererOutput = RecognitionReportRenderer();

  final RecognitionManifest manifest;
  final RecognitionGateThresholds thresholds;
  try {
    manifest = runner.parseManifestJsonString(
      await manifestFile.readAsString(),
    );
    thresholds = gate.parseThresholdsJsonString(
      await thresholdsFile.readAsString(),
    );
  } on RecognitionManifestParseException catch (error) {
    stderr.writeln('Manifest failed to parse: $error');
    exitCode = 1;
    return;
  } on RecognitionGateConfigException catch (error) {
    stderr.writeln('Threshold file failed to parse: $error');
    exitCode = 1;
    return;
  }

  final overall = computeRecognitionMetrics(manifest.cases);
  final RecognitionGateVerdict verdict;
  try {
    verdict = gate.evaluate(overall, thresholds);
  } on RecognitionGateConfigException catch (error) {
    stderr.writeln('Gate evaluation failed: $error');
    exitCode = 1;
    return;
  }

  final report = RecognitionDashboardReport.build(
    manifestSchemaVersion: manifest.schemaVersion,
    overall: overall,
    cases: manifest.cases,
    gate: verdict,
  );

  final rendered = switch (format) {
    'markdown' => rendererOutput.renderMarkdown(report),
    'html' => rendererOutput.renderHtml(report),
    _ => rendererOutput.renderJson(report),
  };
  stdout.write(rendered);
  if (!rendered.endsWith('\n')) stdout.writeln();

  exitCode = verdict.passed ? 0 : 3;
}
