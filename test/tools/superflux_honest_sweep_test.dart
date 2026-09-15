// D9 — SuperFlux onset parameter sweep on the HONEST one-to-one metric.
//
// WHY this file exists even though `onset_recall_sweep_test.dart` already
// sweeps (delta, lambda): that sweep scores "is there ANY detection within
// 120 ms of this label", which is neither one-to-one (one detection can
// satisfy several labels) nor the tolerance the release gate uses. Its
// numbers are therefore NOT comparable with the shipped baseline. This
// harness scores with the merge-elt matcher
// (`computeRecognitionMetrics`, ADR 0509 D5/D8 — Kuhn maximum-cardinality
// one-to-one matching) at the shipped tolerances (25/50/100 ms), and
// additionally with the two-sided greedy matcher
// `real_audio_dsp_baseline.dart` itself used to produce
// `evaluation/recognition/baseline_manifest.json` — so the comparison
// against that manifest's 0.642/0.709/0.674 @50 ms is made under the very
// matcher that produced it, not a different one.
//
// MATCHING IS PER RECORDING. `computeRecognitionMetrics` pools every case's
// events into ONE bipartite matching, which is correct for a manifest of
// short, disjointly-timed cases but NOT for 82 full-length takes whose
// timelines all start at 0 s: pooled, ~19 expected events of other
// recordings sit inside any ±50 ms window and the matcher would happily
// pair them up. So the shipped function is called once per recording (one
// case per call) and only the integer TP/FP/FN counts are summed, using
// `real_audio_dsp_baseline.dart`'s own `OnsetMetrics.merge` + P/R/F1
// getters — this file declares no matcher and no P/R/F1 of its own
// (ADR 0524 D3).
//
// The sweep measures the RAW `SuperFluxOnsetDetector`, framed exactly as
// the live pipeline frames it; the manifest baseline measures the whole
// `ClipAnalyzer`. The apples-to-apples control is therefore the SHIPPED
// CELL (12.0, 1.0, 16) measured by this same harness, and both references
// are printed side by side.
//
// Auto-skips when `ml/data/klangio` is absent (gitignored third-party
// dataset; it lives on the dev box).
//
// Run:
//   flutter test test/tools/superflux_honest_sweep_test.dart
// Optional knobs (both are printed into the report, never applied
// silently):
//   --dart-define=SUPERFLUX_SWEEP_STRIDE=k   every k-th recording id
//   --dart-define=SUPERFLUX_SWEEP_WORKERS=n  concurrent isolates
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_metrics.dart';
import 'package:strumsight/features/live/engine/dsp/superflux_onset_detector.dart';

import '../../tool/benchmarks/real_audio_dsp_baseline.dart'
    show OnsetMetrics, matchOnsetsUs;
import 'klangio_real_ab_test.dart' show dataDir, evalIds, readStrums, readWav;

/// Where the measured table is written.
const String reportPath = 'docs/eval/superflux-honest-sweep-2026-09-15.md';

/// The exact command this report documents, spelled with the knobs the run
/// actually used (both default to these values, so the bare
/// `flutter test test/tools/superflux_honest_sweep_test.dart` is the same
/// run — the defines are written out so the doc never hides a subsample).
String reportCommand({required int stride, required int workers}) =>
    'flutter test --dart-define=SUPERFLUX_SWEEP_STRIDE=$stride '
    '--dart-define=SUPERFLUX_SWEEP_WORKERS=$workers '
    'test/tools/superflux_honest_sweep_test.dart';

/// F1@50 of the shipped honest baseline
/// (`evaluation/recognition/baseline_manifest.json`, metricBlocks.onset,
/// tolerance50000us) — the external reference the shipping rule names.
const double manifestBaselineF1At50 = 0.6739121651650438;
const double manifestBaselinePrecisionAt50 = 0.6423290203327172;
const double manifestBaselineRecallAt50 = 0.7087617914506671;

/// The margin a cell must clear to be allowed to move the shipping
/// constants (D9 rule).
const double shipMargin = 0.02;

const List<double> sweepDeltas = <double>[8, 10, 12, 14];
const List<double> sweepLambdas = <double>[0.7, 1.0, 1.3];
const List<int> sweepMinRiseBands = <int>[12, 16, 20];

/// The tolerances scored, in milliseconds — the shipped list, not a
/// re-declaration (`onsetTolerancesMs` is `[25, 50, 100]`).
const List<int> toleranceList = onsetTolerancesMs;

/// One point of the (delta, lambda, minRiseBands) grid.
final class SweepCell {
  const SweepCell(this.delta, this.lambda, this.minRiseBands);

  final double delta;
  final double lambda;
  final int minRiseBands;

  /// True for the constants `SuperFluxOnsetDetector` ships with today.
  bool get isShipped =>
      delta == _shipped.delta &&
      lambda == _shipped.lambda &&
      minRiseBands == _shipped.minRiseBands;

  String get label =>
      'delta=${delta.toStringAsFixed(0)} lambda=$lambda '
      'minRiseBands=$minRiseBands';
}

/// The shipped detector, read for its PUBLIC defaults — never a re-typed
/// literal (the ADR 0524 D2 convention `onset_detector_variant.dart` follows).
final SuperFluxOnsetDetector _shipped = SuperFluxOnsetDetector(
  sampleRate: 44100,
);

/// The grid, in a fixed order: delta outer, then lambda, then minRiseBands.
final List<SweepCell> sweepGrid = <SweepCell>[
  for (final delta in sweepDeltas)
    for (final lambda in sweepLambdas)
      for (final bands in sweepMinRiseBands) SweepCell(delta, lambda, bands),
];

/// One recording's detections for every cell of [sweepGrid], in grid order.
typedef RecordingRun = (int durationMs, List<List<int>> detectedMsPerCell);

/// Worker body (runs in its own isolate): decodes one take once and streams
/// it through every grid cell's detector. Returns detection times in
/// milliseconds — the same `onsetSec * 1000` convention
/// `tool/benchmarks/onset_ab_benchmark.dart` uses.
RecordingRun sweepRecording(String id) {
  final (pcm, sampleRate) = readWav('$dataDir/recording_${id}_phone.wav');
  final perCell = <List<int>>[];
  for (final cell in sweepGrid) {
    final detector = SuperFluxOnsetDetector(
      sampleRate: sampleRate,
      delta: cell.delta,
      lambda: cell.lambda,
      minRiseBands: cell.minRiseBands,
    );
    final times = <int>[];
    for (
      var start = 0;
      start + detector.window <= pcm.length;
      start += detector.hop
    ) {
      final onsetSec = detector.processFrame(
        Float64List.sublistView(pcm, start, start + detector.window),
      );
      if (onsetSec != null) times.add((onsetSec * 1000).round());
    }
    perCell.add(times);
  }
  return ((pcm.length * 1000 / sampleRate).round(), perCell);
}

/// Micro-averaged scores of one cell over one set of recordings, under both
/// matchers, at every tolerance in [toleranceList].
final class CellScore {
  const CellScore({required this.kuhn, required this.greedy});

  /// Tolerance (ms) -> summed counts from the merge-elt Kuhn matcher.
  final Map<int, OnsetMetrics> kuhn;

  /// Tolerance (ms) -> summed counts from the baseline's greedy matcher.
  final Map<int, OnsetMetrics> greedy;
}

/// Scores [cellIndex] over [ids] with BOTH matchers, one recording at a
/// time. The Kuhn numbers come from the shipped
/// [computeRecognitionMetrics]; the greedy ones from the baseline's own
/// [matchOnsetsUs]. Only the integer counts are summed here.
CellScore scoreCell({
  required int cellIndex,
  required List<String> ids,
  required Map<String, RecordingRun> runs,
  required Map<String, List<double>> groundTruthSec,
}) {
  final kuhn = <int, OnsetMetrics>{
    for (final tolerance in toleranceList)
      tolerance: const OnsetMetrics(
        matched: 0,
        falsePositives: 0,
        falseNegatives: 0,
      ),
  };
  final greedy = <int, OnsetMetrics>{...kuhn};

  for (final id in ids) {
    final (durationMs, perCell) = runs[id]!;
    final detectedMs = perCell[cellIndex];
    final expectedSec = groundTruthSec[id]!;

    final recognitionCase = RecognitionCase(
      caseId: id,
      durationMs: durationMs,
      expectedEvents: <RecognitionExpectedEvent>[
        for (final seconds in expectedSec)
          RecognitionExpectedEvent(
            timeMs: (seconds * 1000).round(),
            kind: RecognitionEventKind.onset,
          ),
      ],
      detectedEvents: <RecognitionDetectedEvent>[
        for (final timeMs in detectedMs)
          RecognitionDetectedEvent(
            timeMs: timeMs,
            kind: RecognitionEventKind.onset,
            accepted: true,
            confidence: 1,
          ),
      ],
    );
    final metrics = computeRecognitionMetrics(<RecognitionCase>[
      recognitionCase,
    ]);
    final byTolerance = <int, RecognitionPrecisionRecallF1>{
      25: metrics.onsetTolerance25Ms,
      50: metrics.onsetTolerance50Ms,
      100: metrics.onsetTolerance100Ms,
    };
    for (final tolerance in toleranceList) {
      final prf1 = byTolerance[tolerance]!;
      kuhn[tolerance] = kuhn[tolerance]!.merge(
        OnsetMetrics(
          matched: prf1.truePositives,
          falsePositives: prf1.falsePositives,
          falseNegatives: prf1.falseNegatives,
        ),
      );
      greedy[tolerance] = greedy[tolerance]!.merge(
        matchOnsetsUs(
          <int>[for (final seconds in expectedSec) (seconds * 1e6).round()],
          <int>[for (final timeMs in detectedMs) timeMs * 1000],
          toleranceUs: tolerance * 1000,
        ),
      );
    }
  }
  return CellScore(kuhn: kuhn, greedy: greedy);
}

/// Runs [ids] through [sweepRecording] on [workers] interleaved lanes, so
/// at most [workers] isolates are alive at once. Lane `l` takes ids
/// `l, l + workers, ...` — the takes are of comparable length, so the lanes
/// finish together without a work-stealing queue.
Future<Map<String, RecordingRun>> runSweep(
  List<String> ids, {
  required int workers,
}) async {
  final results = <String, RecordingRun>{};
  Future<void> lane(int offset) async {
    for (var i = offset; i < ids.length; i += workers) {
      final id = ids[i];
      results[id] = await Isolate.run(() => sweepRecording(id));
    }
  }

  await Future.wait(<Future<void>>[
    for (var offset = 0; offset < workers; offset++) lane(offset),
  ]);
  return results;
}

String _f(double? value) => value == null ? 'n/a' : value.toStringAsFixed(4);

void main() {
  final present = Directory(dataDir).existsSync();

  test(
    'HONEST SWEEP: delta x lambda x minRiseBands on one-to-one P/R/F1',
    () async {
      final stride = int.parse(
        const String.fromEnvironment(
          'SUPERFLUX_SWEEP_STRIDE',
          defaultValue: '1',
        ),
      );
      final workers = int.parse(
        const String.fromEnvironment(
          'SUPERFLUX_SWEEP_WORKERS',
          defaultValue: '8',
        ),
      );

      final allIds =
          Directory(dataDir)
              .listSync()
              .whereType<File>()
              .map((file) => file.uri.pathSegments.last)
              .where((name) => name.endsWith('.strums'))
              .map(
                (name) => name.substring(
                  'recording_'.length,
                  name.length - '.strums'.length,
                ),
              )
              .toList()
            ..sort();
      final ids = <String>[
        for (var i = 0; i < allIds.length; i += stride) allIds[i],
      ];
      final foldIds = <String>[
        for (final id in ids)
          if (evalIds.contains(id)) id,
      ];

      final groundTruthSec = <String, List<double>>{
        for (final id in ids)
          id: <double>[
            for (final (seconds, _) in readStrums(
              '$dataDir/recording_$id.strums',
            ))
              seconds,
          ],
      };
      final labelCount = groundTruthSec.values.fold<int>(
        0,
        (sum, events) => sum + events.length,
      );

      // ignore: avoid_print
      print(
        'HONEST SWEEP: ${sweepGrid.length} cells x ${ids.length} recordings '
        '(stride $stride, of ${allIds.length}), $labelCount labels, '
        'eval fold ${foldIds.length}, $workers workers',
      );

      final wallClock = Stopwatch()..start();
      final runs = await runSweep(ids, workers: workers);
      final detectSeconds = wallClock.elapsedMilliseconds / 1000;

      final audioSeconds =
          runs.values.fold<int>(0, (sum, run) => sum + run.$1) / 1000;

      final allScores = <CellScore>[];
      final foldScores = <CellScore>[];
      for (var i = 0; i < sweepGrid.length; i++) {
        allScores.add(
          scoreCell(
            cellIndex: i,
            ids: ids,
            runs: runs,
            groundTruthSec: groundTruthSec,
          ),
        );
        foldScores.add(
          scoreCell(
            cellIndex: i,
            ids: foldIds,
            runs: runs,
            groundTruthSec: groundTruthSec,
          ),
        );
        // ignore: avoid_print
        print(
          '${sweepGrid[i].label} | all F1@50 kuhn '
          '${_f(allScores[i].kuhn[50]!.f1)} greedy '
          '${_f(allScores[i].greedy[50]!.f1)} | fold F1@50 kuhn '
          '${_f(foldScores[i].kuhn[50]!.f1)}',
        );
      }
      wallClock.stop();
      final totalSeconds = wallClock.elapsedMilliseconds / 1000;

      final shippedIndex = sweepGrid.indexWhere((cell) => cell.isShipped);
      expect(
        shippedIndex,
        isNonNegative,
        reason: 'the grid must contain the shipped cell as its control',
      );
      final shippedAllF1 = allScores[shippedIndex].kuhn[50]!.f1;
      final shippedFoldF1 = foldScores[shippedIndex].kuhn[50]!.f1;
      final shippedGreedyF1 = allScores[shippedIndex].greedy[50]!.f1;

      // The D9 shipping rule, evaluated in code so the verdict is measured
      // rather than eyeballed: beat BOTH references by >= [shipMargin] on
      // all recordings AND not lose on the eval fold.
      final winners = <int>[
        for (var i = 0; i < sweepGrid.length; i++)
          if (!sweepGrid[i].isShipped &&
              allScores[i].greedy[50]!.f1 >=
                  manifestBaselineF1At50 + shipMargin &&
              allScores[i].kuhn[50]!.f1 >= shippedAllF1 + shipMargin &&
              foldScores[i].kuhn[50]!.f1 >= shippedFoldF1)
            i,
      ];

      // The best non-shipped cell, so a negative result is QUANTIFIED:
      // "nothing cleared the bar" only means something next to how far the
      // strongest candidate actually got.
      var bestIndex = -1;
      for (var i = 0; i < sweepGrid.length; i++) {
        if (sweepGrid[i].isShipped) continue;
        if (bestIndex == -1 ||
            allScores[i].kuhn[50]!.f1 > allScores[bestIndex].kuhn[50]!.f1) {
          bestIndex = i;
        }
      }
      final bestAllF1 = allScores[bestIndex].kuhn[50]!.f1;
      final bestFoldF1 = foldScores[bestIndex].kuhn[50]!.f1;
      final allF1At50 = <double>[
        for (final score in allScores) score.kuhn[50]!.f1,
      ];
      final gridSpread =
          allF1At50.reduce(math.max) - allF1At50.reduce(math.min);

      final report = StringBuffer()
        ..writeln('# SuperFlux honest onset sweep (D9)')
        ..writeln()
        ..writeln(
          '- Command: `${reportCommand(stride: stride, workers: workers)}`',
        )
        ..writeln(
          '- Stride: $stride (${stride == 1 ? 'every' : 'every $stride-th'} '
          'recording id of ${allIds.length}) — ${ids.length} recordings '
          'scored, $labelCount labeled strums.',
        )
        ..writeln('- Eval fold: ${foldIds.length} recordings (`evalIds`).')
        ..writeln('- Workers: $workers isolates.')
        ..writeln(
          '- Runtime: ${totalSeconds.toStringAsFixed(1)} s wall clock '
          '(${detectSeconds.toStringAsFixed(1)} s detection over '
          '${audioSeconds.toStringAsFixed(0)} s of audio x '
          '${sweepGrid.length} cells, the rest scoring). MACHINE-DEPENDENT '
          '(ADR 0474/0248) — never a merge gate.',
        )
        ..writeln(
          '- Grid: delta ${sweepDeltas.map((d) => d.toStringAsFixed(0)).join('/')} '
          'x lambda ${sweepLambdas.join('/')} x minRiseBands '
          '${sweepMinRiseBands.join('/')} = ${sweepGrid.length} cells.',
        )
        ..writeln()
        ..writeln('## What is measured')
        ..writeln()
        ..writeln(
          'The RAW `SuperFluxOnsetDetector`, framed as the live pipeline '
          'frames it (window ${_shipped.window}, hop ${_shipped.hop}), over '
          'the Klangio takes. Scoring is ONE-TO-ONE and PER RECORDING:',
        )
        ..writeln()
        ..writeln(
          '- **kuhn** — the shipped `computeRecognitionMetrics` (ADR 0509 '
          'D5/D8: Kuhn maximum-cardinality one-to-one matching, '
          'closest-gap-first, inclusive boundary), called once per '
          'recording; only the integer TP/FP/FN are summed.',
        )
        ..writeln(
          '- **greedy** — `tool/benchmarks/real_audio_dsp_baseline.dart`\'s '
          'own `matchOnsetsUs`, the two-sided sequential matcher that '
          'produced `evaluation/recognition/baseline_manifest.json`. This '
          'is the column that is directly comparable with the manifest '
          'number; Kuhn matches at least as many pairs, so the kuhn column '
          'is the optimistic one.',
        )
        ..writeln()
        ..writeln(
          'Neither matcher is re-implemented here and no P/R/F1 formula is '
          're-declared (ADR 0524 D3): the roll-up arithmetic is the '
          'baseline\'s own `OnsetMetrics`.',
        )
        ..writeln()
        ..writeln('## References')
        ..writeln()
        ..writeln(
          '- Manifest baseline (`ClipAnalyzer`, greedy matcher, all 82): '
          'P ${manifestBaselinePrecisionAt50.toStringAsFixed(3)} / R '
          '${manifestBaselineRecallAt50.toStringAsFixed(3)} / F1 '
          '**${manifestBaselineF1At50.toStringAsFixed(3)}** @50 ms.',
        )
        ..writeln(
          '- Shipped cell measured HERE (raw detector, same corpus): F1@50 '
          'kuhn **${_f(shippedAllF1)}**, greedy **${_f(shippedGreedyF1)}**; '
          'eval fold kuhn **${_f(shippedFoldF1)}**. This is the '
          'apples-to-apples control — the manifest number comes from the '
          'whole analyze pipeline, not from this detector alone.',
        )
        ..writeln()
        ..writeln('## All recordings (n = ${ids.length})')
        ..writeln()
        ..writeln(
          '| delta | lambda | minRiseBands | P@25 | R@25 | F1@25 | P@50 | '
          'R@50 | F1@50 | P@100 | R@100 | F1@100 | F1@50 greedy | TP@50 | '
          'FP@50 | FN@50 |',
        )
        ..writeln(
          '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|',
        );
      for (var i = 0; i < sweepGrid.length; i++) {
        final cell = sweepGrid[i];
        final k = allScores[i].kuhn;
        final at50 = k[50]!;
        final mark = cell.isShipped ? ' **(shipped)**' : '';
        report.writeln(
          '| ${cell.delta.toStringAsFixed(0)}$mark | ${cell.lambda} | '
          '${cell.minRiseBands} | ${_f(k[25]!.precision)} | '
          '${_f(k[25]!.recall)} | ${_f(k[25]!.f1)} | ${_f(at50.precision)} | '
          '${_f(at50.recall)} | ${_f(at50.f1)} | ${_f(k[100]!.precision)} | '
          '${_f(k[100]!.recall)} | ${_f(k[100]!.f1)} | '
          '${_f(allScores[i].greedy[50]!.f1)} | ${at50.matched} | '
          '${at50.falsePositives} | ${at50.falseNegatives} |',
        );
      }
      report
        ..writeln()
        ..writeln('## Eval fold only (n = ${foldIds.length})')
        ..writeln()
        ..writeln(
          '| delta | lambda | minRiseBands | F1@25 | P@50 | R@50 | F1@50 | '
          'F1@100 | F1@50 greedy |',
        )
        ..writeln('|---|---|---|---|---|---|---|---|---|');
      for (var i = 0; i < sweepGrid.length; i++) {
        final cell = sweepGrid[i];
        final k = foldScores[i].kuhn;
        final mark = cell.isShipped ? ' **(shipped)**' : '';
        report.writeln(
          '| ${cell.delta.toStringAsFixed(0)}$mark | ${cell.lambda} | '
          '${cell.minRiseBands} | ${_f(k[25]!.f1)} | ${_f(k[50]!.precision)} | '
          '${_f(k[50]!.recall)} | ${_f(k[50]!.f1)} | ${_f(k[100]!.f1)} | '
          '${_f(foldScores[i].greedy[50]!.f1)} |',
        );
      }
      report
        ..writeln()
        ..writeln('## Verdict')
        ..writeln()
        ..writeln(
          'A cell may move the shipping constants only when it clears ALL '
          'three bars: greedy F1@50 on all recordings >= manifest baseline '
          '+ ${shipMargin.toStringAsFixed(2)} '
          '(${(manifestBaselineF1At50 + shipMargin).toStringAsFixed(4)}), '
          'kuhn F1@50 on all recordings >= the shipped cell measured here + '
          '${shipMargin.toStringAsFixed(2)} '
          '(${(shippedAllF1 + shipMargin).toStringAsFixed(4)}), and no loss '
          'against the shipped cell on the eval fold '
          '(>= ${_f(shippedFoldF1)}).',
        )
        ..writeln();
      if (winners.isEmpty) {
        report
          ..writeln(
            '**NEGATIVE RESULT — nothing ships.** No cell of the '
            '${sweepGrid.length}-point grid cleared the bar, so `delta 12.0 / '
            'lambda 1.0 / minRiseBands 16` stay exactly as they are.',
          )
          ..writeln()
          ..writeln(
            'How close it got: the best non-shipped cell is '
            '`${sweepGrid[bestIndex].label}` at F1@50 ${_f(bestAllF1)} kuhn '
            '(fold ${_f(bestFoldF1)}), i.e. '
            '**${(bestAllF1 - shippedAllF1) >= 0 ? '+' : ''}'
            '${(bestAllF1 - shippedAllF1).toStringAsFixed(4)}** against the '
            'shipped cell — ${(shipMargin - (bestAllF1 - shippedAllF1)).toStringAsFixed(4)} '
            'short of the ${shipMargin.toStringAsFixed(2)} bar. The whole '
            'grid spans only ${gridSpread.toStringAsFixed(4)} F1@50 end to '
            'end, so these three knobs are NOT where the remaining onset '
            'error lives.',
          )
          ..writeln()
          ..writeln(
            'Two facts the table makes measurable, both worth more than the '
            'sweep itself:',
          )
          ..writeln()
          ..writeln(
            '1. **The raw detector scores BELOW the manifest.** Shipped cell '
            'here ${_f(shippedGreedyF1)} greedy vs the manifest\'s '
            '${manifestBaselineF1At50.toStringAsFixed(4)} under the SAME '
            'matcher and corpus. The manifest measures `ClipAnalyzer`, which '
            'is this detector plus the `StrumAnalyzer` gating on top, so '
            'that gating is worth more F1 than any point of this grid — it '
            'is removing false positives the detector emits.',
          )
          ..writeln(
            '2. **Most of the loss at +-50 ms is TIMING, not misses.** The '
            'shipped cell\'s recall goes '
            '${_f(allScores[shippedIndex].kuhn[25]!.recall)} @25 ms -> '
            '${_f(allScores[shippedIndex].kuhn[50]!.recall)} @50 ms -> '
            '${_f(allScores[shippedIndex].kuhn[100]!.recall)} @100 ms. The '
            'attacks ARE detected; they land late/early by 50-100 ms. A '
            'threshold knob cannot fix a latency offset, which is why the '
            'grid is flat.',
          );
      } else {
        report.writeln('**Cells clearing the bar:**');
        report.writeln();
        for (final i in winners) {
          report.writeln(
            '- ${sweepGrid[i].label}: all F1@50 kuhn '
            '${_f(allScores[i].kuhn[50]!.f1)} / greedy '
            '${_f(allScores[i].greedy[50]!.f1)}, fold F1@50 '
            '${_f(foldScores[i].kuhn[50]!.f1)}',
          );
        }
      }

      File(reportPath).writeAsStringSync(report.toString());
      // ignore: avoid_print
      print(
        'wrote $reportPath in ${totalSeconds.toStringAsFixed(1)} s; '
        'winners=${winners.length}',
      );

      expect(
        labelCount,
        stride == 1 ? 11767 : greaterThan(0),
        reason: 'the full corpus carries 11767 labeled strums',
      );
      expect(
        runs.length,
        ids.length,
        reason: 'every selected recording must have produced detections',
      );
      expect(
        shippedAllF1,
        greaterThan(0),
        reason: 'the shipped control must score on the honest metric',
      );
    },
    skip: present
        ? false
        : 'ml/data/klangio absent (gitignored dataset lives on the dev box)',
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
