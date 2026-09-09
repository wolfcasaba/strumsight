/// Three-way chord-engine comparison harness (E14-R27, ADR 0539).
///
/// SDD Ch14 §4.5 asks which chord path should ship: the legacy NNLS-chroma
/// to dictionary to Viterbi decoder, the shipped chord CRNN
/// (`assets/ml/chord_crnn.bin`), or a hybrid of the two. This file is the
/// SCORING half of that question and deliberately not the answer:
///
/// * it takes several engines' chord timelines over the SAME fixtures,
///   projects each into the merged `computeRecognitionMetrics` contract
///   (E14-R08, ADR 0509) and renders one table;
/// * it asserts INVARIANTS only — every engine saw the same input bytes,
///   every engine was scored on every fixture — and never ranks;
/// * [ChordComparisonReport.decision] is a constant: `NEEDS-MEASUREMENT`.
///   Choosing an engine needs the real corpus of SDD Ch14 §7.1, which does
///   not exist yet (`docs/eval/chord-corpus-plan.md`); picking a winner off
///   synthetic fixtures is exactly the "blind threshold rewrite" Ch14 §12/1
///   forbids.
///
/// Which metrics the table shows is itself part of the contract. A chord
/// timeline carries a label and a time span, not a per-event confidence, so
/// the confidence-shaped metrics (accepted accuracy, coverage, ECE, Brier)
/// would be degenerate here — they are NOT rendered, and
/// [ChordComparisonReport.omittedMetricsNote] says so in the output rather
/// than leaving a reader to assume a `1.0000` means something.
///
/// This file never opens a file or a socket and imports nothing outside the
/// live feature: the engines themselves are run by the caller (see the
/// round's harness test).
library;

import 'recognition_metrics.dart';
import 'recognition_release_gate.dart' show recognitionMetricExtractors;

/// One labelled span of a chord timeline.
final class ChordTimelineSegment {
  ChordTimelineSegment({
    required this.label,
    required this.startSec,
    required this.endSec,
  }) {
    if (startSec.isNaN || endSec.isNaN || endSec < startSec) {
      throw ArgumentError.value(
        '[$startSec, $endSec]',
        'span',
        'must be a non-decreasing, non-NaN time span',
      );
    }
  }

  /// A chord label (`Am`, `C`) or the reserved no-chord label.
  final String label;
  final double startSec;
  final double endSec;
}

/// A fixture every engine is run over: the input's identity, its duration
/// and the ground truth for it.
final class ChordComparisonFixture {
  const ChordComparisonFixture({
    required this.fixtureId,
    required this.inputSha256,
    required this.durationSec,
    required this.expected,
  });

  final String fixtureId;

  /// Hash of the PCM the engines were fed. The harness compares it across
  /// engines: two engines scored on different bytes are not comparable, and
  /// this catches a resampled or re-generated fixture silently drifting.
  final String inputSha256;

  final double durationSec;

  /// The fixture's ground-truth chord spans.
  final List<ChordTimelineSegment> expected;
}

/// One engine's output for one fixture.
final class ChordEngineRun {
  const ChordEngineRun({
    required this.engineId,
    required this.fixtureId,
    required this.inputSha256,
    required this.segments,
  });

  /// A stable engine identifier, e.g. `nnls-viterbi`, `chord-crnn`,
  /// `hybrid`.
  final String engineId;

  final String fixtureId;

  /// Hash of the bytes THIS engine was fed.
  final String inputSha256;

  final List<ChordTimelineSegment> segments;
}

enum ChordComparisonErrorKind {
  /// An engine's run is missing for a fixture, or a run names an unknown
  /// fixture.
  incompleteCoverage,

  /// Two engines were fed different bytes for the same fixture.
  inputHashMismatch,

  /// The same engine/fixture pair appears twice.
  duplicateRun,
}

final class ChordComparisonException implements Exception {
  const ChordComparisonException(this.kind, this.message);

  final ChordComparisonErrorKind kind;
  final String message;

  @override
  String toString() => 'ChordComparisonException(${kind.name}): $message';
}

/// The metric paths this comparison renders — chord-shaped only, in a fixed
/// order. Every entry is a key of [recognitionMetricExtractors], so a metric
/// renamed in the merged contract breaks this list loudly instead of
/// rendering a blank column.
const List<String> chordComparisonMetricPaths = <String>[
  'chordWeightedAccuracy.value',
  'chordMacroF1.value',
  'chordNoChordF1.f1',
  'chordMacroF1.weakestSupportedRecall',
  'falseVisibleChordEventsPerMinute.value',
];

/// The only verdict this harness can produce.
const String chordComparisonDecision = 'NEEDS-MEASUREMENT';

/// The scored comparison: one [RecognitionMetrics] per engine over the same
/// fixtures, plus the constant [decision].
final class ChordComparisonReport {
  const ChordComparisonReport({
    required this.engineIds,
    required this.fixtureIds,
    required this.metricsByEngine,
    required this.inputSha256ByFixture,
  });

  /// Sorted, so the table's column order never depends on map iteration.
  final List<String> engineIds;

  /// Sorted.
  final List<String> fixtureIds;

  final Map<String, RecognitionMetrics> metricsByEngine;

  /// The single input hash every engine was verified against, per fixture.
  final Map<String, String> inputSha256ByFixture;

  /// Always [chordComparisonDecision] — see the library doc.
  String get decision => chordComparisonDecision;

  String get omittedMetricsNote =>
      'Accepted accuracy, coverage, ECE and Brier are omitted on purpose: a '
      'chord TIMELINE carries no per-event confidence, so those metrics '
      'would be degenerate constants here, not measurements.';

  /// A deterministic Markdown table: one row per metric, one column per
  /// engine, plus the fixture/input provenance and the decision line.
  String renderMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Chord engine comparison (E14-R27)')
      ..writeln()
      ..writeln('- Decision: **$decision**')
      ..writeln('- Engines: ${engineIds.join(', ')}')
      ..writeln('- Fixtures: ${fixtureIds.length}')
      ..writeln();
    for (final fixtureId in fixtureIds) {
      final hash = inputSha256ByFixture[fixtureId];
      buffer.writeln('- `$fixtureId` input sha256: `$hash`');
    }
    final header = engineIds.join(' | ');
    final rule = engineIds.map((_) => '---:').join('|');
    buffer
      ..writeln()
      ..writeln('| Metric | $header |')
      ..writeln('|---|$rule|');
    for (final metricPath in chordComparisonMetricPaths) {
      final cells = <String>[];
      for (final engineId in engineIds) {
        final metrics = metricsByEngine[engineId]!;
        final sample = recognitionMetricExtractors[metricPath]!(metrics);
        final value = sample.value;
        cells.add(value == null ? 'n/a' : value.toStringAsFixed(4));
      }
      buffer.writeln('| $metricPath | ${cells.join(' | ')} |');
    }
    buffer
      ..writeln()
      ..writeln(omittedMetricsNote);
    return buffer.toString();
  }
}

/// Scores every engine over every fixture. Throws
/// [ChordComparisonException] when the runs do not form a complete,
/// same-input grid — an incomplete comparison is not a weaker comparison, it
/// is a wrong one.
ChordComparisonReport compareChordEngines({
  required List<ChordComparisonFixture> fixtures,
  required List<ChordEngineRun> runs,
}) {
  final fixtureById = <String, ChordComparisonFixture>{
    for (final fixture in fixtures) fixture.fixtureId: fixture,
  };
  final fixtureIds = fixtureById.keys.toList()..sort();
  final engineIds = <String>{for (final run in runs) run.engineId}.toList()
    ..sort();

  final runByKey = <String, ChordEngineRun>{};
  for (final run in runs) {
    if (!fixtureById.containsKey(run.fixtureId)) {
      throw ChordComparisonException(
        ChordComparisonErrorKind.incompleteCoverage,
        'engine "${run.engineId}" produced a run for unknown fixture '
        '"${run.fixtureId}"',
      );
    }
    final key = '${run.engineId} ${run.fixtureId}';
    if (runByKey.containsKey(key)) {
      throw ChordComparisonException(
        ChordComparisonErrorKind.duplicateRun,
        'engine "${run.engineId}" has two runs for fixture '
        '"${run.fixtureId}"',
      );
    }
    runByKey[key] = run;
  }

  for (final fixtureId in fixtureIds) {
    final expectedHash = fixtureById[fixtureId]!.inputSha256;
    for (final engineId in engineIds) {
      final run = runByKey['$engineId $fixtureId'];
      if (run == null) {
        throw ChordComparisonException(
          ChordComparisonErrorKind.incompleteCoverage,
          'engine "$engineId" has no run for fixture "$fixtureId"',
        );
      }
      if (run.inputSha256 != expectedHash) {
        throw ChordComparisonException(
          ChordComparisonErrorKind.inputHashMismatch,
          'engine "$engineId" was fed ${run.inputSha256} for fixture '
          '"$fixtureId", but the fixture declares $expectedHash — the '
          'engines were not compared on the same input',
        );
      }
    }
  }

  final metricsByEngine = <String, RecognitionMetrics>{};
  for (final engineId in engineIds) {
    final cases = <RecognitionCase>[
      for (final fixtureId in fixtureIds)
        buildChordComparisonCase(
          fixture: fixtureById[fixtureId]!,
          run: runByKey['$engineId $fixtureId']!,
        ),
    ];
    metricsByEngine[engineId] = computeRecognitionMetrics(cases);
  }

  return ChordComparisonReport(
    engineIds: List<String>.unmodifiable(engineIds),
    fixtureIds: List<String>.unmodifiable(fixtureIds),
    metricsByEngine: Map<String, RecognitionMetrics>.unmodifiable(
      metricsByEngine,
    ),
    inputSha256ByFixture: Map<String, String>.unmodifiable(<String, String>{
      for (final fixtureId in fixtureIds)
        fixtureId: fixtureById[fixtureId]!.inputSha256,
    }),
  );
}

/// Projects one fixture and one engine run into a [RecognitionCase].
///
/// A chord SPAN becomes a chord EVENT stamped at the span's start: that is
/// the instant the user sees the label change, and it is what the merged
/// metric set already scores (`chordToleranceMs` = 250 ms around the
/// expected change). Consecutive spans carrying the same label are merged
/// first, so an engine that internally re-emits the same chord every hop is
/// not punished for it.
///
/// Every detected event is `accepted: true` with `confidence: 0`: a timeline
/// has no per-event confidence, and `0` is a value the report never reads
/// (see [ChordComparisonReport.omittedMetricsNote]) — it is not a claim that
/// the engine was unconfident.
RecognitionCase buildChordComparisonCase({
  required ChordComparisonFixture fixture,
  required ChordEngineRun run,
}) {
  final expected = <RecognitionExpectedEvent>[
    for (final segment in mergeAdjacentChordSegments(fixture.expected))
      RecognitionExpectedEvent(
        timeMs: (segment.startSec * 1000).round(),
        kind: RecognitionEventKind.chord,
        chordLabel: segment.label,
      ),
  ];
  final detected = <RecognitionDetectedEvent>[
    for (final segment in mergeAdjacentChordSegments(run.segments))
      RecognitionDetectedEvent(
        timeMs: (segment.startSec * 1000).round(),
        kind: RecognitionEventKind.chord,
        accepted: true,
        confidence: 0,
        chordLabel: segment.label,
      ),
  ];
  return RecognitionCase(
    caseId: '${run.engineId}/${fixture.fixtureId}',
    durationMs: (fixture.durationSec * 1000).round(),
    expectedEvents: expected,
    detectedEvents: detected,
  );
}

/// Merges consecutive same-label spans into one span.
List<ChordTimelineSegment> mergeAdjacentChordSegments(
  List<ChordTimelineSegment> input,
) {
  final merged = <ChordTimelineSegment>[];
  for (final segment in input) {
    if (merged.isNotEmpty && merged.last.label == segment.label) {
      final open = merged.removeLast();
      merged.add(
        ChordTimelineSegment(
          label: open.label,
          startSec: open.startSec,
          endSec: segment.endSec,
        ),
      );
      continue;
    }
    merged.add(segment);
  }
  return merged;
}
