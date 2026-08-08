import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/data/practice_session_result_history_mapper.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/vision/public.dart';

void main() {
  test('vision is optional and explicit null preserves value semantics', () {
    final beforeTheRound = _result();
    final explicitNull = _result(vision: null);

    expect(beforeTheRound, explicitNull);
    expect(beforeTheRound.hashCode, explicitNull.hashCode);
  });

  test(
    'audio result and history entry are byte-for-byte equivalent with vision',
    () {
      final audioOnly = _result();
      final visionEnabled = _result(vision: _visionResult());

      expect(_audioProjection(visionEnabled), _audioProjection(audioOnly));

      final mapper = PracticeSessionResultHistoryMapper(
        now: () => DateTime.utc(2026, 8, 8),
        detailEnabled: true,
        modeCode: 'strumPattern',
        sourceCode: 'builtin',
        definitionId: 'builtin.quarter-downstrokes.v1',
        displayTitle: 'Quarter downstrokes',
        skillTags: const <String>['rhythm'],
      );
      expect(
        mapper.toHistoryEntry(visionEnabled),
        mapper.toHistoryEntry(audioOnly),
      );
    },
  );
}

String _audioProjection(PracticeSessionResult result) =>
    jsonEncode(<String, Object?>{
      'id': result.id,
      'activeDurationMicros': result.activeDuration.inMicroseconds,
      'pausedDurationMicros': result.pausedDuration.inMicroseconds,
      'finishReason': result.finishReason.code,
      'highestStableTempo': result.highestStableTempo?.bpm,
      'coachingSummary': result.coachingSummary,
      'attempts': result.attempts
          .map(
            (attempt) => <String, Object?>{
              'index': attempt.index,
              'tempo': attempt.tempo.bpm,
              'outcome': attempt.outcome.name,
              'verdictCount': attempt.verdicts.length,
              'completion': attempt.metrics.completion.toString(),
              'rhythm': attempt.metrics.rhythm.toString(),
              'direction': attempt.metrics.direction.toString(),
              'chord': attempt.metrics.chord.toString(),
              'overall': attempt.metrics.overall.toString(),
              'totalTargets': attempt.metrics.totalTargets,
              'resolvedTargets': attempt.metrics.resolvedTargets,
              'maxCombo': attempt.metrics.maxCombo,
              'scorePoints': attempt.metrics.scorePoints,
              'meanAbsoluteOffsetMicros':
                  attempt.metrics.meanAbsoluteOffset.inMicroseconds,
              'timingBiasMicros': attempt.metrics.timingBias.inMicroseconds,
            },
          )
          .toList(growable: false),
    });

PracticeSessionResult _result({VisionSessionResult? vision}) =>
    PracticeSessionResult(
      id: 'practice-session',
      activeDuration: const Duration(seconds: 30),
      pausedDuration: const Duration(seconds: 2),
      attempts: <PracticeAttemptResult>[
        PracticeAttemptResult(
          index: 0,
          tempo: const Tempo(96),
          metrics: const PracticeMetrics(
            completion: MetricAvailable(1),
            rhythm: MetricAvailable(0.9),
            direction: MetricAvailable(0.8),
            chord: MetricNotApplicable(),
            overall: MetricAvailable(0.9),
            totalTargets: 8,
            resolvedTargets: 7,
            maxCombo: 5,
            scorePoints: 900,
            meanAbsoluteOffset: Duration(milliseconds: 12),
            timingBias: Duration(milliseconds: -2),
          ),
          verdicts: const <PracticeVerdict>[],
          outcome: PracticeAttemptOutcome.passed,
        ),
      ],
      finishReason: PracticeFinishReason.completedAllTargets,
      highestStableTempo: const Tempo(96),
      coachingSummary: const <String>[],
      vision: vision,
    );

VisionSessionResult _visionResult() => VisionSessionResult(
  session: VisionSession(
    id: VisionSessionId.create('vision-session'),
    startedAt: DateTime.utc(2026),
  ),
  endedAt: DateTime.utc(2026, 1, 1, 0, 1),
  endReason: VisionSessionEndReason.explicitStop,
  qualitySummary: VisionQualitySummary.fromFrames(<VisionFrameQuality>[
    VisionFrameQuality(
      thresholdsVersion: 'test-v1',
      framing: VisionMetricState.good,
      lighting: VisionLighting.good,
      blur: VisionMetricState.good,
      stability: VisionMetricState.good,
      roiCoverage: VisionMetricState.good,
      overall: VisionMetricState.good,
      meanLuminance: 100,
      highlightClippingRatio: 0,
      shadowClippingRatio: 0,
      sharpness: 20,
      cameraMotion: 0,
      roiCoverageRatio: 1,
    ),
  ]),
  calibrationState: CalibrationLossState.tracking,
  sessionSummary: const <VisionInsight>[],
  observedFrameCount: 1,
);
