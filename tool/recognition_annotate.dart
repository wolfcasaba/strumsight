/// Runnable recognition-annotation validator + two-annotator agreement CLI
/// (E14-R07, ADR 0359).
///
/// Usage:
///   dart run tool/recognition_annotate.dart
///   dart run tool/recognition_annotate.dart --pair PATH
///   dart run tool/recognition_annotate.dart --pair PATH --tolerance-ms 30
///
/// Defaults to the small, two-annotator CI fixture
/// (`evaluation/recognition/fixtures/annotation_pair.json`). Validates the
/// pair against the annotation contract (ADR 0359 D1-D3) and prints the
/// deterministic `AgreementReport` JSON to stdout and nothing else: the same
/// pair and tolerance always produce byte-identical stdout, so this output
/// can be diffed or pasted verbatim into a baseline document. Parse and I/O
/// failures are reported on stderr with a non-zero exit code.
library;

import 'dart:io';

import 'package:strumsight/features/live/data/evaluation/recognition_annotation_parser.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_annotation.dart';

void main(List<String> arguments) async {
  var pairPath = 'evaluation/recognition/fixtures/annotation_pair.json';
  var toleranceMs = 50;
  for (var i = 0; i < arguments.length; i++) {
    if (arguments[i] == '--pair' && i + 1 < arguments.length) {
      pairPath = arguments[i + 1];
      i++;
    } else if (arguments[i] == '--tolerance-ms' && i + 1 < arguments.length) {
      final parsed = int.tryParse(arguments[i + 1]);
      if (parsed == null || parsed < 0) {
        stderr.writeln('Invalid --tolerance-ms value: ${arguments[i + 1]}');
        exitCode = 2;
        return;
      }
      toleranceMs = parsed;
      i++;
    } else if (arguments[i] == '--help') {
      stdout.writeln(
        'Usage: dart run tool/recognition_annotate.dart '
        '[--pair <path>] [--tolerance-ms <ms>]',
      );
      return;
    }
  }

  final pairFile = File(pairPath);
  if (!await pairFile.exists()) {
    stderr.writeln('Annotation pair not found: $pairPath');
    exitCode = 2;
    return;
  }

  const parser = RecognitionAnnotationParser();
  try {
    final pair = parser.parseJsonString(await pairFile.readAsString());
    final calculator = AnnotationAgreementCalculator(toleranceMs: toleranceMs);
    final report = calculator.compute(pair);
    stdout.write(report.toDeterministicJson());
    stdout.writeln();
  } on RecognitionAnnotationParseException catch (error) {
    stderr.writeln('Annotation pair failed to parse: $error');
    exitCode = 1;
  }
}
