/// Onset-detector A/B benchmark (E14-R16, ADR 0524).
///
/// Runs the four [OnsetVariantId] functions over the SAME case list and
/// scores every one of them with the merge-elt `computeRecognitionMetrics`
/// (ADR 0509) — this file never declares its own tolerance list, matcher, or
/// P/R/F1 (ADR 0524 D3). Two output channels (ADR 0524 D4):
///
///  - [OnsetAbReport] — deterministic, input-only (case ids/events/algorithmic
///    latency + the merge-elt metric tree). No timestamp, wall-clock, or CPU
///    value is ever read or written here.
///  - [OnsetAbTiming] — wall-clock/CPU, explicitly machine-dependent
///    (`deviceId` + `buildSha`), never a merge gate (ADR 0474/0248).
///
/// The pure core (`OnsetAbCase`, [runOnsetVariant], [buildOnsetAbReport],
/// [manifestJson], [renderOnsetAbMarkdown]) takes no `dart:io` dependency —
/// only `main` touches the filesystem, mirroring
/// `real_audio_dsp_baseline.dart`'s shape.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/features/live/data/evaluation/recognition_evaluation_runner.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_metrics.dart';
import 'package:strumsight/features/live/engine/dsp/onset_detector_variant.dart';

/// The four variants this round measures, in the fixed order they appear in
/// the report (ADR 0524 D1).
const List<OnsetVariantId> onsetAbVariantIds = OnsetVariantId.values;

// ---------------------------------------------------------------------
// Pure core.
// ---------------------------------------------------------------------

/// One recording's PCM plus its hand-annotated onset ground truth — the
/// SAME input every variant in [buildOnsetAbReport] receives (ADR 0524 D1).
class OnsetAbCase {
  const OnsetAbCase({
    required this.caseId,
    required this.sampleRate,
    required this.durationMs,
    required this.pcm,
    required this.expectedEvents,
  });

  final String caseId;
  final int sampleRate;
  final int durationMs;
  final Float64List pcm;
  final List<RecognitionExpectedEvent> expectedEvents;
}

/// Runs [id] over [abCase], framing its PCM into consecutive
/// `variant.window`-sample frames advanced by `variant.hop` (identical
/// framing for every variant). Each confirmed onset becomes an accepted
/// [RecognitionDetectedEvent] plus one algorithmic-latency sample:
/// `decisionMs - onsetMs`, where the decision instant is the END of the
/// frame whose `processFrame` call returned the onset — deterministic and
/// input-only (ADR 0524 D4/5.5), matching
/// `RecognitionCase.detectionLatenciesMs`'s convention.
RecognitionCase runOnsetVariant(OnsetVariantId id, OnsetAbCase abCase) {
  final variant = createOnsetDetectorVariant(id, sampleRate: abCase.sampleRate);
  final window = variant.window;
  final hop = variant.hop;
  final pcm = abCase.pcm;
  final detectedEvents = <RecognitionDetectedEvent>[];
  final detectionLatenciesMs = <int>[];

  var frameIndex = 0;
  var offset = 0;
  while (offset + window <= pcm.length) {
    final frame = Float64List.sublistView(pcm, offset, offset + window);
    final onsetSec = variant.processFrame(frame);
    if (onsetSec != null) {
      final onsetMs = onsetSec * 1000;
      final decisionMs = (frameIndex * hop + window) * 1000 / abCase.sampleRate;
      detectedEvents.add(
        RecognitionDetectedEvent(
          timeMs: onsetMs.round(),
          kind: RecognitionEventKind.onset,
          accepted: true,
          confidence: 1.0,
        ),
      );
      detectionLatenciesMs.add((decisionMs - onsetMs).round());
    }
    offset += hop;
    frameIndex++;
  }

  return RecognitionCase(
    caseId: abCase.caseId,
    durationMs: abCase.durationMs,
    expectedEvents: abCase.expectedEvents,
    detectedEvents: detectedEvents,
    detectionLatenciesMs: detectionLatenciesMs,
  );
}

/// Scores [cases] through the merge-elt contract ONLY — no second matcher,
/// tolerance list, or P/R/F1 (ADR 0524 D3). This is the exact function both
/// [buildOnsetAbReport] and [onsetAbManifestJson] rely on; a hand-built case
/// passed here exercises the benchmark's real scoring path, not a
/// re-derivation of it.
RecognitionEvaluationReport scoreCases(List<RecognitionCase> cases) =>
    RecognitionEvaluationReport(
      manifestSchemaVersion: supportedRecognitionManifestSchemaVersion,
      caseCount: cases.length,
      overall: computeRecognitionMetrics(cases),
    );

/// The full deterministic A/B report: one merge-elt
/// [RecognitionEvaluationReport] per variant, over the SAME [caseCount]
/// cases (ADR 0524 D1/D3). Byte-identical across repeated runs on the same
/// input (ADR 0524 D4) — carries no timestamp, wall-clock, or CPU value.
class OnsetAbReport {
  const OnsetAbReport({required this.caseCount, required this.perVariant});

  final int caseCount;
  final Map<OnsetVariantId, RecognitionEvaluationReport> perVariant;

  Map<String, Object?> toJson() => <String, Object?>{
    'caseCount': caseCount,
    'onsetTolerancesMs': onsetTolerancesMs,
    'variants': <String, Object?>{
      for (final id in onsetAbVariantIds) id.name: perVariant[id]!.toJson(),
    },
  };

  /// A stable, timestamp-free JSON rendering (ADR 0524 D4): the same
  /// [caseCount] cases always produce byte-identical output.
  String toDeterministicJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Builds the deterministic report by running every variant over every case
/// (ADR 0524 D1: same case list, same tolerances, same matcher).
OnsetAbReport buildOnsetAbReport(List<OnsetAbCase> cases) {
  final perVariant = <OnsetVariantId, RecognitionEvaluationReport>{
    for (final id in onsetAbVariantIds)
      id: scoreCases([for (final abCase in cases) runOnsetVariant(id, abCase)]),
  };
  return OnsetAbReport(caseCount: cases.length, perVariant: perVariant);
}

String _fmt(double? value) =>
    value == null ? 'not measured' : value.toStringAsFixed(4);

/// Markdown rendering of [report] — the Pareto-view + per-tolerance table
/// `docs/eval/onset-detector-ab.md` describes. A `null` metric (no
/// annotation to score against) renders as "not measured", never `0`
/// (ADR 0509 D6).
String renderOnsetAbMarkdown(OnsetAbReport report) {
  final buffer = StringBuffer()
    ..writeln('# Onset detector A/B report')
    ..writeln()
    ..writeln('- Cases: ${report.caseCount}')
    ..writeln('- Tolerances (ms): $onsetTolerancesMs')
    ..writeln();
  for (final id in onsetAbVariantIds) {
    final r = report.perVariant[id]!;
    buffer
      ..writeln('## ${id.name}')
      ..writeln()
      ..writeln(createOnsetDetectorVariant(id, sampleRate: 44100).describe())
      ..writeln()
      ..writeln('| tolerance (ms) | precision | recall | f1 | TP | FP | FN |')
      ..writeln('|---|---|---|---|---|---|---|');
    final cells = <int, RecognitionPrecisionRecallF1>{
      25: r.overall.onsetTolerance25Ms,
      50: r.overall.onsetTolerance50Ms,
      100: r.overall.onsetTolerance100Ms,
    };
    for (final toleranceMs in onsetTolerancesMs) {
      final m = cells[toleranceMs]!;
      buffer.writeln(
        '| $toleranceMs | ${_fmt(m.precision)} | ${_fmt(m.recall)} | '
        '${_fmt(m.f1)} | ${m.truePositives} | ${m.falsePositives} | '
        '${m.falseNegatives} |',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        '- latencyP50Ms: ${_fmt(r.overall.latencyP50Ms.value)}, '
        'latencyP95Ms: ${_fmt(r.overall.latencyP95Ms.value)}',
      )
      ..writeln();
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------
// Manifest round-trip (ADR 0524 D5): `RecognitionEvaluationRunner`
// re-reads exactly what this file writes.
// ---------------------------------------------------------------------

Map<String, Object?> _expectedEventToJson(RecognitionExpectedEvent e) =>
    <String, Object?>{
      'timeMs': e.timeMs,
      'kind': e.kind.name,
      'direction': e.direction?.name,
      'chordLabel': e.chordLabel,
    };

Map<String, Object?> _detectedEventToJson(RecognitionDetectedEvent d) =>
    <String, Object?>{
      'timeMs': d.timeMs,
      'kind': d.kind.name,
      'accepted': d.accepted,
      'confidence': d.confidence,
      'direction': d.direction?.name,
      'chordLabel': d.chordLabel,
    };

Map<String, Object?> _caseToManifestJson(RecognitionCase recognitionCase) =>
    <String, Object?>{
      'caseId': recognitionCase.caseId,
      'player': recognitionCase.player,
      'device': recognitionCase.device,
      'guitar': recognitionCase.guitar,
      'room': recognitionCase.room,
      'durationMs': recognitionCase.durationMs,
      'expectedEvents': [
        for (final e in recognitionCase.expectedEvents) _expectedEventToJson(e),
      ],
      'detectedEvents': [
        for (final d in recognitionCase.detectedEvents) _detectedEventToJson(d),
      ],
      'confidenceObservations': [
        for (final o in recognitionCase.confidenceObservations)
          <String, Object?>{'rawScore': o.rawScore, 'correct': o.correct},
      ],
      'detectionLatenciesMs': recognitionCase.detectionLatenciesMs,
    };

/// A `schemaVersion: "1.0"` manifest for [cases] — `RecognitionManifest`'s
/// exact shape, re-readable by `RecognitionEvaluationRunner.runFromJsonString`
/// (ADR 0524 D5).
Map<String, Object?> manifestJson(List<RecognitionCase> cases) =>
    <String, Object?>{
      'schemaVersion': supportedRecognitionManifestSchemaVersion,
      'cases': [for (final c in cases) _caseToManifestJson(c)],
    };

/// The per-variant manifest [buildOnsetAbReport] can be cross-checked
/// against (ADR 0524 D5): re-runs [id] over [cases] and serialises the
/// resulting [RecognitionCase]s.
Map<String, Object?> onsetAbManifestJson(
  OnsetVariantId id,
  List<OnsetAbCase> cases,
) => manifestJson([for (final abCase in cases) runOnsetVariant(id, abCase)]);

// ---------------------------------------------------------------------
// Timing channel (ADR 0524 D4) — explicitly machine-dependent, never a
// merge gate (ADR 0474/0248). Uses `Stopwatch` (wall-clock), so its VALUES
// vary run to run and machine to machine by design; none of it feeds
// [OnsetAbReport].
// ---------------------------------------------------------------------

class OnsetAbVariantTiming {
  const OnsetAbVariantTiming({
    required this.totalProcessingMicros,
    required this.audioSeconds,
  });

  final int totalProcessingMicros;
  final double audioSeconds;

  double get microsPerAudioSecond =>
      audioSeconds == 0 ? 0 : totalProcessingMicros / audioSeconds;

  Map<String, Object?> toJson() => <String, Object?>{
    'totalProcessingMicros': totalProcessingMicros,
    'audioSeconds': audioSeconds,
    'microsPerAudioSecond': microsPerAudioSecond,
  };
}

class OnsetAbTiming {
  const OnsetAbTiming({
    required this.deviceId,
    required this.buildSha,
    required this.perVariant,
  });

  final String deviceId;
  final String buildSha;
  final Map<OnsetVariantId, OnsetAbVariantTiming> perVariant;

  Map<String, Object?> toJson() => <String, Object?>{
    'note':
        'MACHINE-DEPENDENT wall-clock/CPU timing (ADR 0474/0248) — never a '
        'merge gate, never diffed for correctness.',
    'deviceId': deviceId,
    'buildSha': buildSha,
    'variants': <String, Object?>{
      for (final entry in perVariant.entries)
        entry.key.name: entry.value.toJson(),
    },
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Wall-clock/CPU timing for every variant over [cases] — machine-dependent
/// by construction, kept entirely separate from [OnsetAbReport].
OnsetAbTiming measureOnsetAbTiming(
  List<OnsetAbCase> cases, {
  required String deviceId,
  required String buildSha,
}) {
  final totalAudioSeconds = cases.fold<double>(
    0,
    (sum, c) => sum + c.durationMs / 1000,
  );
  final perVariant = <OnsetVariantId, OnsetAbVariantTiming>{
    for (final id in onsetAbVariantIds)
      id: () {
        final stopwatch = Stopwatch()..start();
        for (final abCase in cases) {
          runOnsetVariant(id, abCase);
        }
        stopwatch.stop();
        return OnsetAbVariantTiming(
          totalProcessingMicros: stopwatch.elapsedMicroseconds,
          audioSeconds: totalAudioSeconds,
        );
      }(),
  };
  return OnsetAbTiming(
    deviceId: deviceId,
    buildSha: buildSha,
    perVariant: perVariant,
  );
}

// ---------------------------------------------------------------------
// CLI shell (`real_audio_dsp_baseline.dart`'s shape): corpus-directory
// argument, `dart:io` only here. No committed corpus exists (ADR 0249) —
// this reads a directory of `<stem>.wav` + `<stem>.onsets.json`
// (`{"onsets": [seconds, ...]}`) pairs supplied externally.
// ---------------------------------------------------------------------

void main([List<String> arguments = const []]) {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'usage: dart run tool/benchmarks/onset_ab_benchmark.dart '
      '<corpus-directory> [<output-directory>]\n'
      'corpus-directory pairs: <stem>.wav + <stem>.onsets.json '
      '(`{"onsets": [seconds, ...]}`)',
    );
    exitCode = 64;
    return;
  }

  final corpus = Directory(arguments.first);
  if (!corpus.existsSync()) {
    stderr.writeln('corpus directory does not exist: ${corpus.path}');
    exitCode = 66;
    return;
  }
  final outputDir = Directory(arguments.length > 1 ? arguments[1] : corpus.path)
    ..createSync(recursive: true);

  final wavFiles =
      corpus
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.wav'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  final cases = <OnsetAbCase>[];
  final skipped = <Map<String, String>>[];
  for (final wav in wavFiles) {
    final stem = wav.path.substring(0, wav.path.length - '.wav'.length);
    final sidecar = File('$stem.onsets.json');
    final fileName = wav.uri.pathSegments.last;
    if (!sidecar.existsSync()) {
      skipped.add({
        'file': fileName,
        'error': 'no matching .onsets.json sidecar',
      });
      continue;
    }
    try {
      final decoded = WavDecoder.decode(wav.readAsBytesSync());
      if (decoded == null) {
        throw const FormatException('unsupported or invalid WAV');
      }
      final (pcm, sampleRate) = decoded;
      final sidecarJson = jsonDecode(sidecar.readAsStringSync());
      if (sidecarJson is! Map<String, Object?> ||
          sidecarJson['onsets'] is! List) {
        throw const FormatException(
          'sidecar must be a JSON object with an "onsets" array (seconds)',
        );
      }
      final expectedEvents = [
        for (final seconds in (sidecarJson['onsets']! as List).cast<num>())
          RecognitionExpectedEvent(
            timeMs: (seconds.toDouble() * 1000).round(),
            kind: RecognitionEventKind.onset,
          ),
      ];
      cases.add(
        OnsetAbCase(
          caseId: fileName,
          sampleRate: sampleRate,
          durationMs: (pcm.length * 1000 / sampleRate).round(),
          pcm: Float64List.fromList(pcm),
          expectedEvents: expectedEvents,
        ),
      );
    } on Object catch (error) {
      skipped.add({'file': fileName, 'error': error.toString()});
    }
  }

  if (cases.isEmpty) {
    stderr.writeln(
      'no usable cases found under ${corpus.path} (${skipped.length} '
      'skipped) — writing an empty-case report',
    );
  }

  final report = buildOnsetAbReport(cases);
  File(
    '${outputDir.path}${Platform.pathSeparator}onset-ab-report.json',
  ).writeAsStringSync(report.toDeterministicJson());
  File(
    '${outputDir.path}${Platform.pathSeparator}onset-ab-report.md',
  ).writeAsStringSync(renderOnsetAbMarkdown(report));

  final timing = measureOnsetAbTiming(
    cases,
    deviceId: Platform.operatingSystem,
    buildSha: Platform.environment['ONSET_AB_BUILD_SHA'] ?? 'unknown',
  );
  File(
    '${outputDir.path}${Platform.pathSeparator}onset-ab-timing.json',
  ).writeAsStringSync(timing.toJsonString());

  for (final id in onsetAbVariantIds) {
    File(
      '${outputDir.path}${Platform.pathSeparator}onset-ab-manifest-${id.name}.json',
    ).writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(onsetAbManifestJson(id, cases)),
    );
  }

  stdout.writeln('cases: ${cases.length}, skipped: ${skipped.length}');
  if (skipped.isNotEmpty) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({'skipped': skipped}),
    );
  }
}
