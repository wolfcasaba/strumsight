import 'dart:async';

import 'package:strumsight/features/analyze/public.dart';

import '../data/shadow/shadow_diff_report.dart';
import '../domain/analysis_document.dart';
import '../domain/analysis_input.dart';
import 'analysis_isolate_runner.dart';

/// Injectable V1 boundary used by [ShadowAnalysisRunner].
typedef LegacyClipAnalyzer =
    FutureOr<AnalyzeResult> Function(List<double> samples, int sampleRate);

/// The user-visible V1 value plus optional Lab-only V2 diagnostics.
final class ShadowAnalysisRunResult {
  const ShadowAnalysisRunResult({required this.v1Result, this.diffReport});

  /// This remains the exact V1 result regardless of shadow outcome.
  final AnalyzeResult v1Result;

  /// Null unless both independent Lab gates allowed a V2 shadow run.
  final ShadowDiffReport? diffReport;
}

/// Runs V2 only as an isolated Lab diagnostic alongside an unchanged V1 call.
///
/// This class deliberately has no Riverpod dependency and no production
/// caller. A future, separately approved wiring round provides the concrete
/// V2 runner and explicit runtime gates.
final class ShadowAnalysisRunner {
  const ShadowAnalysisRunner({required this.v1Analyze, required this.v2Runner});

  final LegacyClipAnalyzer v1Analyze;
  final AnalysisRunner v2Runner;

  /// Runs V1 unconditionally. V2 starts only when both independently supplied
  /// gates are true; a V2 error or cancellation cannot fail V1.
  Future<ShadowAnalysisRunResult> run({
    required List<double> samples,
    required int sampleRate,
    required AnalysisDocument v2Input,
    required bool labModeActive,
    required bool audioAnalysisV2Enabled,
  }) async {
    final v1Watch = Stopwatch()..start();
    final v1Result = await v1Analyze(samples, sampleRate);
    v1Watch.stop();

    if (!labModeActive || !audioAnalysisV2Enabled) {
      return ShadowAnalysisRunResult(v1Result: v1Result);
    }

    final v2Watch = Stopwatch()..start();
    AnalysisRunResult? v2Result;
    var v2Failed = false;
    try {
      final handle = v2Runner.start(
        AnalysisRunRequest(
          seed: v2Input,
          audio: ValidatedPcmAnalysisInput(
            input: PcmAnalysisInput(
              samples: samples,
              sampleRate: sampleRate,
              channelCount: 1,
              source: v2Input.input.source,
            ),
          ),
        ),
      );
      v2Result = await handle.result;
      v2Failed =
          v2Result.document == null ||
          (v2Result.completion != AnalysisCompletionStatus.complete &&
              v2Result.completion != AnalysisCompletionStatus.degraded);
    } on Object {
      v2Failed = true;
    } finally {
      v2Watch.stop();
    }

    return ShadowAnalysisRunResult(
      v1Result: v1Result,
      diffReport: _buildReport(
        v1Result: v1Result,
        v1Runtime: v1Watch.elapsed,
        v2Result: v2Result,
        v2Runtime: v2Watch.elapsed,
        v2Failed: v2Failed,
      ),
    );
  }

  ShadowDiffReport _buildReport({
    required AnalyzeResult v1Result,
    required Duration v1Runtime,
    required AnalysisRunResult? v2Result,
    required Duration v2Runtime,
    required bool v2Failed,
  }) {
    final document = v2Result?.document;
    final tempoPoints = document?.timeline.tempoPoints;
    return ShadowDiffReport(
      v1EventCount: v1Result.strums.length,
      v2EventCount: document?.timeline.events.length ?? 0,
      v1ChordSegmentCount: v1Result.chords.length,
      v2ChordSegmentCount: document?.timeline.chordSegments.length ?? 0,
      v1Bpm: v1Result.bpm,
      v2Bpm: tempoPoints == null || tempoPoints.isEmpty
          ? null
          : tempoPoints.first.bpm,
      v1Duration: _durationFromSeconds(v1Result.durationSec),
      v2Duration: document?.timeline.duration,
      v1Runtime: v1Runtime,
      v2Runtime: v2Runtime,
      v2Failed: v2Failed,
    );
  }

  Duration _durationFromSeconds(double seconds) => Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );
}
