/// Runnable grouped-recognition evaluation harness (E14-R08, ADR 0509).
///
/// Usage:
///   dart run tool/recognition_evaluate.dart
///   dart run tool/recognition_evaluate.dart --manifest PATH
///
/// Defaults to the small, synthetic CI fixture
/// (`evaluation/recognition/fixtures/ci_manifest.json`). Pass `--manifest`
/// to point at an external, licensed real-recording manifest for a manual
/// run (ADR 0509 D9 — that data never lives in this repo).
///
/// Prints the deterministic `RecognitionEvaluationReport` JSON to stdout
/// and nothing else: the same manifest and code always produce
/// byte-identical stdout (ADR 0509 D6). Parse and I/O failures are reported
/// on stderr with a non-zero exit code.
library;

import 'dart:io';

import 'package:strumsight/features/live/data/evaluation/recognition_evaluation_runner.dart';

void main(List<String> arguments) async {
  var manifestPath = 'evaluation/recognition/fixtures/ci_manifest.json';
  for (var i = 0; i < arguments.length; i++) {
    if (arguments[i] == '--manifest' && i + 1 < arguments.length) {
      manifestPath = arguments[i + 1];
      i++;
    } else if (arguments[i] == '--help') {
      stdout.writeln(
        'Usage: dart run tool/recognition_evaluate.dart [--manifest <path>]',
      );
      return;
    }
  }

  final manifestFile = File(manifestPath);
  if (!await manifestFile.exists()) {
    stderr.writeln('Manifest not found: $manifestPath');
    exitCode = 2;
    return;
  }

  const runner = RecognitionEvaluationRunner();
  try {
    final report = runner.runFromJsonString(await manifestFile.readAsString());
    stdout.write(report.toDeterministicJson());
    stdout.writeln();
  } on RecognitionManifestParseException catch (error) {
    stderr.writeln('Manifest failed to parse: $error');
    exitCode = 1;
  }
}
