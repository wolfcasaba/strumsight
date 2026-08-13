/// Runnable Audio Analysis evaluation harness (E06-R29, ADR 0249).
///
/// Usage:
///   dart run tool/audio_analysis_evaluate.dart
///   dart run tool/audio_analysis_evaluate.dart --manifest PATH
///
/// Defaults to the small, synthetic CI fixture
/// (`evaluation/analysis/fixtures/ci_manifest.json`). Pass `--manifest` to
/// point at an external, licensed real-audio manifest for a manual run (see
/// `evaluation/analysis/README.md` — that data never lives in this repo).
///
/// Prints the deterministic `EvaluationReport` JSON to stdout and nothing
/// else: the same manifest and code always produce byte-identical stdout, so
/// this output can be diffed or pasted verbatim into a baseline document.
/// Parse and I/O failures are reported on stderr with a non-zero exit code.
library;

import 'dart:io';

import 'package:strumsight/features/audio_analysis/data/evaluation/evaluation_manifest_parser.dart';
import 'package:strumsight/features/audio_analysis/data/evaluation/evaluation_runner.dart';

void main(List<String> arguments) async {
  var manifestPath = 'evaluation/analysis/fixtures/ci_manifest.json';
  for (var i = 0; i < arguments.length; i++) {
    if (arguments[i] == '--manifest' && i + 1 < arguments.length) {
      manifestPath = arguments[i + 1];
      i++;
    } else if (arguments[i] == '--help') {
      stdout.writeln(
        'Usage: dart run tool/audio_analysis_evaluate.dart [--manifest <path>]',
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

  const parser = EvaluationManifestParser();
  const runner = EvaluationRunner();
  try {
    final manifest = parser.parseJsonString(await manifestFile.readAsString());
    final report = runner.run(manifest);
    stdout.write(report.toDeterministicJson());
    stdout.writeln();
  } on ManifestParseException catch (error) {
    stderr.writeln('Manifest failed to parse: $error');
    exitCode = 1;
  }
}
