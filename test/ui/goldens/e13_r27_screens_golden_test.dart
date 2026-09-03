// Golden snapshots of the E13-R27 analysis results screens (overview,
// timeline, compare, metric detail), at a compact portrait phone
// (412×915) and the same frame at textScaler 2.0 — the two frames the
// round brief §7/A9 requires. Pattern and sizing follow the merged
// `test/ui/goldens/e13_r26_screens_golden_test.dart` precedent: `SsDarkTheme`
// (the app's actual runtime dark theme, `strumsight_app.dart` — ADR 0466),
// not the legacy `AppTheme`.
//
// Recorded on x86_64 (ADR 0426, §0.0/B/B5) via `tools/golden-x86.sh record`
// — NOT `flutter test --update-goldens` on this (aarch64) box.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_dark_theme.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_hotspot.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input_summary.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_insight.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric_catalog.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_provenance.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_timeline.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/comparison/analysis_comparison.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_compare_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_metric_detail_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_overview_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_timeline_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/controllers/overview_view_model.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _compactPortrait = Size(412, 915);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SsDarkTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

AnalysisMetricResult _metric(
  String id,
  CapabilityStatus status, {
  AnalysisMetricValue? value,
  CapabilityUnavailableReason? unavailableReason,
  String unit = 's',
}) => AnalysisMetricResult(
  id: id,
  version: 1,
  status: status,
  confidence: status == CapabilityStatus.available ? 0.9 : 0.4,
  unit: unit,
  sampleCount: 10,
  evidence: const <String>[],
  value: value,
  unavailableReason: unavailableReason,
);

AnalysisDocument _document() => AnalysisDocument(
  id: 'e13-r27-golden-fixture',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026, 8, 20),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(minutes: 2, seconds: 5),
    sampleRate: 48000,
    channelCount: 1,
    fingerprint: 'golden',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1.0.0',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{},
    dspConfigHash: 'cfg',
    modelManifestIds: const <String>[],
    inputFingerprint: 'golden',
    platform: 'android',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: 0.82,
    peakDbfs: -3,
    rmsDbfs: -18,
    noiseFloorDbfs: -60,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: 0,
  ),
  capabilities: const <CapabilityReport>[],
  timeline: AnalysisTimeline(duration: const Duration(minutes: 2, seconds: 5)),
  metrics: <AnalysisMetricResult>[
    _metric(
      AnalysisMetricId.timingMeanAbsoluteError,
      CapabilityStatus.available,
      value: ScalarMetricValue(0.05),
    ),
    _metric(
      AnalysisMetricId.rhythmRushDragBias,
      CapabilityStatus.degraded,
      value: ScalarMetricValue(0.01),
    ),
    _metric(
      AnalysisMetricId.dynamicsStrokeStrengthCv,
      CapabilityStatus.unavailable,
      unavailableReason: CapabilityUnavailableReason.clipTooShort,
    ),
    _metric(
      AnalysisMetricId.harmonyChordCoverage,
      CapabilityStatus.notApplicable,
    ),
  ],
  hotspots: <AnalysisHotspot>[
    AnalysisHotspot(
      id: 'h1',
      kind: AnalysisHotspotKind.timing,
      start: const Duration(seconds: 20),
      end: const Duration(seconds: 21),
      severity: AnalysisHotspotSeverity.medium,
      confidence: .8,
      metricIds: const <String>[],
      evidenceIds: const <String>[],
    ),
  ],
  insights: <AnalysisInsight>[
    AnalysisInsight(
      id: 'i-rec',
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
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);

AnalysisComparison _comparison() => AnalysisComparison(
  beforeAnalysisId: 'before',
  afterAnalysisId: 'after',
  metrics: <MetricComparison>[
    MetricComparison(
      metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
      direction: MetricComparisonDirection.improved,
      confidence: 0.8,
      sampleCount: 12,
      beforeValue: 40,
      afterValue: 30,
      absoluteDelta: -10,
      relativeDelta: -0.25,
    ),
    MetricComparison(
      metricId: AnalysisMetricId.dynamicsDrift,
      direction: MetricComparisonDirection.inconclusive,
      confidence: 0.5,
      sampleCount: 6,
      inconclusiveReason: ComparisonInconclusiveReason.inputQualityDiverged,
    ),
  ],
);

OverviewMetricCard _detailCard() => const OverviewMetricCard(
  metricId: 'metric.golden.v1',
  metricLabel: 'Timing accuracy',
  unit: 'ms',
  state: OverviewMetricCardState.available,
  valueText: '45 ms',
  confidence: 0.9,
  statusLabel: 'High confidence',
  reasonText: '',
  tipText: '',
  isUsable: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('analysis overview — $suffix', (tester) async {
      await _pump(
        tester,
        AnalysisOverviewScreen(document: _document()),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r27_analysis_overview_$suffix');
    });

    testWidgets('analysis timeline — $suffix', (tester) async {
      await _pump(
        tester,
        AnalysisTimelineScreen(document: _document()),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r27_analysis_timeline_$suffix');
    });

    testWidgets('analysis compare — $suffix', (tester) async {
      await _pump(
        tester,
        AnalysisCompareScreen(comparison: _comparison()),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r27_analysis_compare_$suffix');
    });

    testWidgets('analysis metric detail — $suffix', (tester) async {
      await _pump(
        tester,
        AnalysisMetricDetailScreen(
          metrics: <OverviewMetricCard>[_detailCard()],
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r27_analysis_metric_detail_$suffix');
    });
  }
}
