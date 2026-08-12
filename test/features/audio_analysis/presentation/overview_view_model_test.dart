import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input_summary.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_insight.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric_catalog.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_provenance.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_timeline.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/presentation/controllers/overview_view_model.dart';

class _RecordingLabels implements OverviewLabels {
  const _RecordingLabels();

  @override
  String actionDisabledTooltip(AnalysisRecommendedAction action) =>
      'tooltip ${action.name}';

  @override
  String actionLabel(AnalysisRecommendedAction action) =>
      'label ${action.name}';

  @override
  String completionLabel(AnalysisCompletion completion) => 'completion';

  @override
  String confidenceHigh() => 'high';

  @override
  String confidenceLow() => 'low';

  @override
  String confidenceMedium() => 'medium';

  @override
  String formatDbfs(double dbfs) => '${dbfs.toStringAsFixed(1)} dB';

  @override
  String formatDuration(Duration duration) => '${duration.inMilliseconds} ms';

  @override
  String formatMetricValue(AnalysisMetricResult metric) {
    final value = metric.value;
    if (value is ScalarMetricValue) return '${value.value} ${metric.unit}';
    if (value is PercentageMetricValue) {
      return '${(value.value * 100).toStringAsFixed(0)}%';
    }
    if (value is DurationMetricValue) {
      return '${value.value.inMilliseconds} ms';
    }
    return '?';
  }

  @override
  String formatRatio(double ratio) => '${(ratio * 100).toStringAsFixed(1)}%';

  @override
  String inputSubtitle(AnalysisInputSummary input) =>
      '${input.source.name} ${input.duration.inSeconds}s';

  @override
  String insightKindLabel(AnalysisInsightKind kind) => 'kind ${kind.name}';

  @override
  String insightKindTitle(AnalysisInsightKind kind) => 'title ${kind.name}';

  @override
  String insightMessage(String messageKey, Map<String, String> args) =>
      'msg:$messageKey';

  @override
  String metricLabel(String metricId) => 'metric:$metricId';

  @override
  String notApplicableStatusLabel() => 'NA';

  @override
  String notApplicableValuePlaceholder() => '—';

  @override
  String overviewTitle(AnalysisDocument document) =>
      'overview ${document.id}';

  @override
  String unavailableReason(CapabilityUnavailableReason reason) =>
      'reason ${reason.name}';

  @override
  String unavailableStatusLabel() => 'UNAVAILABLE';

  @override
  String unavailableTip(CapabilityUnavailableReason reason) =>
      'tip ${reason.name}';

  @override
  String unavailableValuePlaceholder() => '—';

  @override
  String warningHeadline(AnalysisWarning warning) =>
      'warn ${warning.messageKey}';
}

AnalysisDocument _baseDocument({
  List<AnalysisMetricResult> metrics = const <AnalysisMetricResult>[],
  List<AnalysisInsight> insights = const <AnalysisInsight>[],
  List<AnalysisWarning> signalWarnings = const <AnalysisWarning>[],
  AnalysisCompletion? completion,
  SignalQualityReport? signal,
  Duration duration = const Duration(seconds: 42),
}) {
  return AnalysisDocument(
    id: 'doc-1',
    schemaVersion: analysisDocumentSchemaVersion,
    createdAt: DateTime.utc(2026, 8, 12),
    mode: AnalysisMode.freePlay,
    input: AnalysisInputSummary(
      source: AnalysisInputSource.microphone,
      duration: duration,
      sampleRate: 48000,
      channelCount: 1,
      fingerprint: 'fp',
    ),
    provenance: AnalysisProvenance(
      appVersion: '1.0.0',
      analyzerVersion: '1',
      pipelineVersion: '1',
      stageVersions: const <String, String>{},
      dspConfigHash: 'cfg',
      modelManifestIds: const <String>[],
      inputFingerprint: 'fp',
      platform: 'android',
      featureFlagSnapshot: const <String, bool>{},
    ),
    signalQuality: signal ??
        SignalQualityReport(
          overall: 0,
          peakDbfs: -3,
          rmsDbfs: -18,
          noiseFloorDbfs: -60,
          clippedSampleRatio: 0,
          silentRatio: 0,
          tonalness: 0,
          warnings: signalWarnings,
        ),
    capabilities: const <CapabilityReport>[],
    timeline: AnalysisTimeline(duration: duration),
    metrics: metrics,
    hotspots: const [],
    insights: insights,
    warnings: const [],
    completion: completion ??
        AnalysisCompletion(status: AnalysisCompletionStatus.complete),
  );
}

AnalysisMetricResult _metric(
  String id,
  CapabilityStatus status, {
  AnalysisMetricValue? value,
  double confidence = 0.9,
  CapabilityUnavailableReason? unavailableReason,
  int sampleCount = 8,
  String unit = 'ms',
}) {
  return AnalysisMetricResult(
    id: id,
    version: 1,
    status: status,
    confidence: confidence,
    unit: unit,
    sampleCount: sampleCount,
    evidence: const <String>[],
    value: value,
    unavailableReason: unavailableReason,
  );
}

void main() {
  group('OverviewViewModel.from', () {
    test('header formats duration, completion and source subtitle', () {
      final view = OverviewViewModel.from(
        _baseDocument(),
        labels: const _RecordingLabels(),
      );

      expect(view.header.title, 'overview doc-1');
      expect(view.header.subtitle, contains('microphone'));
      expect(view.header.durationText, '42000 ms');
      expect(view.header.completionLabel, 'completion');
    });

    test('signal-quality card formats every signal measurement', () {
      final view = OverviewViewModel.from(
        _baseDocument(
          signal: SignalQualityReport(
            overall: 0,
            peakDbfs: -3.4,
            rmsDbfs: -18.2,
            noiseFloorDbfs: -55.7,
            clippedSampleRatio: 0.0123,
            silentRatio: 0.0001,
            tonalness: 0,
          ),
        ),
        labels: const _RecordingLabels(),
      );

      expect(view.signalQuality.peakDbfsText, '-3.4 dB');
      expect(view.signalQuality.rmsDbfsText, '-18.2 dB');
      expect(view.signalQuality.noiseFloorDbfsText, '-55.7 dB');
      expect(view.signalQuality.clippedRatioText, '1.2%');
      expect(view.signalQuality.silentRatioText, '0.0%');
      expect(view.signalQuality.warningHeadlines, isEmpty);
    });

    test(
      'metric state mapping covers all five states without confidence threshold',
      () {
        final view = OverviewViewModel.from(
          _baseDocument(
            metrics: <AnalysisMetricResult>[
              _metric(
                AnalysisMetricId.timingMeanAbsoluteError,
                CapabilityStatus.available,
                value: ScalarMetricValue(0.042),
                unit: 's',
              ),
              _metric(
                AnalysisMetricId.rhythmRushDragBias,
                CapabilityStatus.degraded,
                value: ScalarMetricValue(-0.015),
                unit: 's',
              ),
              _metric(
                AnalysisMetricId.dynamicsStrokeStrengthCv,
                CapabilityStatus.unavailable,
                unavailableReason: CapabilityUnavailableReason.clipTooShort,
              ),
              _metric(
                AnalysisMetricId.harmonyChordCoverage,
                CapabilityStatus.unavailable,
                unavailableReason: CapabilityUnavailableReason.confidenceTooLow,
                confidence: 0.2,
              ),
              _metric(
                AnalysisMetricId.rhythmInferredIoiConsistency,
                CapabilityStatus.notApplicable,
              ),
            ],
          ),
          labels: const _RecordingLabels(),
        );

        final byId = <String, OverviewMetricCard>{
          for (final card in view.details) card.metricId: card,
        };
        expect(
          byId[AnalysisMetricId.timingMeanAbsoluteError]!.state,
          OverviewMetricCardState.available,
        );
        expect(
          byId[AnalysisMetricId.timingMeanAbsoluteError]!.statusLabel,
          'high',
        );
        expect(
          byId[AnalysisMetricId.rhythmRushDragBias]!.state,
          OverviewMetricCardState.degraded,
        );
        expect(
          byId[AnalysisMetricId.dynamicsStrokeStrengthCv]!.state,
          OverviewMetricCardState.unavailable,
        );
        expect(
          byId[AnalysisMetricId.dynamicsStrokeStrengthCv]!.reasonText,
          'reason clipTooShort',
        );
        expect(
          byId[AnalysisMetricId.dynamicsStrokeStrengthCv]!.tipText,
          'tip clipTooShort',
        );
        expect(
          byId[AnalysisMetricId.harmonyChordCoverage]!.state,
          OverviewMetricCardState.lowConfidence,
        );
        expect(
          byId[AnalysisMetricId.harmonyChordCoverage]!.statusLabel,
          'low',
        );
        expect(
          byId[AnalysisMetricId.harmonyChordCoverage]!.reasonText,
          'reason confidenceTooLow',
        );
        expect(
          byId[AnalysisMetricId.rhythmInferredIoiConsistency]!.state,
          OverviewMetricCardState.notApplicable,
        );
      },
    );

    test('primary metrics expose exactly one card per primary category', () {
      final view = OverviewViewModel.from(
        _baseDocument(
          metrics: <AnalysisMetricResult>[
            _metric(
              AnalysisMetricId.timingMeanAbsoluteError,
              CapabilityStatus.available,
              value: ScalarMetricValue(0.05),
              unit: 's',
            ),
            _metric(
              AnalysisMetricId.timingTargetMedianAbsoluteError,
              CapabilityStatus.available,
              value: ScalarMetricValue(0.04),
              unit: 's',
            ),
            _metric(
              AnalysisMetricId.rhythmRushDragBias,
              CapabilityStatus.available,
              value: ScalarMetricValue(0.0),
              unit: 's',
            ),
            _metric(
              AnalysisMetricId.dynamicsStrokeStrengthCv,
              CapabilityStatus.available,
              value: ScalarMetricValue(0.18),
            ),
            _metric(
              AnalysisMetricId.harmonyChordCoverage,
              CapabilityStatus.available,
              value: ScalarMetricValue(0.92),
            ),
          ],
        ),
        labels: const _RecordingLabels(),
      );

      expect(
        view.primaryMetrics.map((card) => card.metricId).toList(),
        <String>[
          AnalysisMetricId.timingMeanAbsoluteError,
          AnalysisMetricId.rhythmRushDragBias,
          AnalysisMetricId.dynamicsStrokeStrengthCv,
          AnalysisMetricId.harmonyChordCoverage,
        ],
      );
      expect(view.details.length, 5);
    });

    test('unavailable card value text is a placeholder, not a zero', () {
      final view = OverviewViewModel.from(
        _baseDocument(
          metrics: <AnalysisMetricResult>[
            _metric(
              AnalysisMetricId.dynamicsStrokeStrengthCv,
              CapabilityStatus.unavailable,
              unavailableReason: CapabilityUnavailableReason.inputTooNoisy,
            ),
          ],
        ),
        labels: const _RecordingLabels(),
      );

      final card = view.details.single;
      expect(card.state, OverviewMetricCardState.unavailable);
      expect(card.valueText, '—');
      expect(card.isUsable, isFalse);
    });

    test('insight card binds action label and disabled tooltip', () {
      final view = OverviewViewModel.from(
        _baseDocument(
          insights: <AnalysisInsight>[
            AnalysisInsight(
              id: 'i-1',
              ruleId: 'r',
              ruleVersion: '1',
              priority: AnalysisInsightPriority.high,
              kind: AnalysisInsightKind.recommendation,
              factIds: const <String>[],
              messageKey: 'analysisInsightRushBias',
              messageArgs: const <String, String>{'milliseconds': '12'},
              recommendedAction: AnalysisRecommendedAction.slowDown,
            ),
          ],
        ),
        labels: const _RecordingLabels(),
      );

      expect(view.insights, hasLength(1));
      final card = view.insights.single;
      expect(card.body, 'msg:analysisInsightRushBias');
      expect(card.actionLabel, 'label slowDown');
      expect(card.actionTooltip, 'tooltip slowDown');
    });

    test('completion label is forwarded to labels', () {
      final view = OverviewViewModel.from(
        _baseDocument(
          completion: AnalysisCompletion(
            status: AnalysisCompletionStatus.failed,
            failureCode: 'internal_failure',
          ),
        ),
        labels: const _RecordingLabels(),
      );
      expect(view.header.completionLabel, 'completion');
    });
  });
}
