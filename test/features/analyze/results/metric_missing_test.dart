// A1-A3 (SDD Ch13 Kör 27, ADR 0286 §1/§3): the three mandatory metric-display
// cells from the brief's §6.1 threshold matrix — below threshold (no
// measurement), at threshold (measured, low/medium confidence) and above
// threshold (measured, high confidence). Every cell pumps the REAL
// [MetricCard]/[AnalysisOverviewScreen] widget built from a REAL
// [OverviewViewModel] and asserts on the rendered TEXT (§0.0/B/B7) — never a
// pure formatter call or a widget-type-only predicate. This is a MEGŐRZÉS
// round (§0.0/B/B6): the behaviour already exists; this file locks it in.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_overview_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/controllers/overview_view_model.dart';
import 'package:strumsight/l10n/app_localizations.dart';

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

AnalysisDocument _document(List<AnalysisMetricResult> metrics) =>
    AnalysisDocument(
      id: 'metric-missing-fixture',
      schemaVersion: analysisDocumentSchemaVersion,
      createdAt: DateTime.utc(2026),
      mode: AnalysisMode.freePlay,
      input: AnalysisInputSummary(
        source: AnalysisInputSource.microphone,
        duration: const Duration(minutes: 1),
        sampleRate: 48000,
        channelCount: 1,
        fingerprint: 'f',
      ),
      provenance: AnalysisProvenance(
        appVersion: '1',
        analyzerVersion: '1',
        pipelineVersion: '1',
        stageVersions: const <String, String>{},
        dspConfigHash: 'x',
        modelManifestIds: const <String>[],
        inputFingerprint: 'f',
        platform: 'test',
        featureFlagSnapshot: const <String, bool>{},
      ),
      signalQuality: SignalQualityReport(
        overall: 0.7,
        peakDbfs: -3,
        rmsDbfs: -18,
        noiseFloorDbfs: -60,
        clippedSampleRatio: 0,
        silentRatio: 0,
        tonalness: 0,
      ),
      capabilities: const <CapabilityReport>[],
      timeline: AnalysisTimeline(duration: const Duration(minutes: 1)),
      metrics: metrics,
      hotspots: const <AnalysisHotspot>[],
      insights: const <AnalysisInsight>[],
      warnings: const <AnalysisWarning>[],
      completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
    );

Widget _harness(AnalysisDocument document) => MaterialApp(
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: AnalysisOverviewScreen(document: document),
);

/// Tall enough that every primary metric card (plus the header, signal
/// quality card and confidence legend above them) is actually built — a
/// plain (non-builder) `ListView` still only builds the children within its
/// viewport, so a too-short window silently drops later cards from the
/// element tree `find.text` searches (matches the pinned overview test's
/// own `Size(400, 1200+)` pattern).
Future<void> _pumpTall(WidgetTester tester, AnalysisDocument document) async {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness(document));
  await tester.pumpAndSettle();
}

void main() {
  group(
    'threshold matrix (§6.1) — below/at/above, real widget + real text',
    () {
      testWidgets(
        'below threshold (unavailable): never "0", explicit no-data text',
        (tester) async {
          final document = _document(<AnalysisMetricResult>[
            _metric(
              AnalysisMetricId.timingMeanAbsoluteError,
              CapabilityStatus.unavailable,
              unavailableReason: CapabilityUnavailableReason.clipTooShort,
            ),
          ]);

          await _pumpTall(tester, document);

          expect(find.text('0'), findsNothing);
          expect(find.text('0 ms'), findsNothing);
          expect(find.text('—'), findsOneWidget);
          expect(find.text('Measurement unavailable'), findsOneWidget);
          expect(
            find.text('The recording is too short to measure this.'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'below threshold (notApplicable): its own state, distinct from '
        'unavailable',
        (tester) async {
          final document = _document(<AnalysisMetricResult>[
            _metric(
              AnalysisMetricId.harmonyChordCoverage,
              CapabilityStatus.notApplicable,
            ),
          ]);

          await _pumpTall(tester, document);

          expect(find.text('0'), findsNothing);
          expect(find.text('—'), findsOneWidget);
          expect(
            find.text('Not applicable for this recording'),
            findsOneWidget,
          );
          expect(find.text('Measurement unavailable'), findsNothing);
        },
      );

      testWidgets(
        'at threshold (degraded): a real measured value, medium-confidence '
        'marking',
        (tester) async {
          final document = _document(<AnalysisMetricResult>[
            _metric(
              AnalysisMetricId.rhythmRushDragBias,
              CapabilityStatus.degraded,
              value: ScalarMetricValue(0.123),
            ),
          ]);

          await _pumpTall(tester, document);

          expect(find.text('123 ms'), findsOneWidget);
          // The always-visible confidence legend (§3 scope) contributes
          // one occurrence on its own; requiring >= 2 proves the card
          // carries its OWN badge too.
          expect(find.text('Medium confidence'), findsAtLeastNWidgets(2));
        },
      );

      testWidgets(
        'above threshold (available): a real measured value, high-confidence '
        'marking',
        (tester) async {
          final document = _document(<AnalysisMetricResult>[
            _metric(
              AnalysisMetricId.dynamicsStrokeStrengthCv,
              CapabilityStatus.available,
              value: ScalarMetricValue(0.456),
            ),
          ]);

          await _pumpTall(tester, document);

          expect(find.text('456 ms'), findsOneWidget);
          // Same legend caveat as the degraded cell above.
          expect(find.text('High confidence'), findsAtLeastNWidgets(2));
        },
      );
    },
  );

  testWidgets(
    'A3 — confidence is visible for every card, not only the first one',
    (tester) async {
      final document = _document(<AnalysisMetricResult>[
        _metric(
          AnalysisMetricId.timingMeanAbsoluteError,
          CapabilityStatus.available,
          value: ScalarMetricValue(0.05),
        ),
        _metric(
          AnalysisMetricId.rhythmRushDragBias,
          CapabilityStatus.degraded,
          value: ScalarMetricValue(0.02),
        ),
        _metric(
          AnalysisMetricId.dynamicsStrokeStrengthCv,
          CapabilityStatus.unavailable,
          unavailableReason: CapabilityUnavailableReason.confidenceTooLow,
        ),
        _metric(
          AnalysisMetricId.harmonyChordCoverage,
          CapabilityStatus.notApplicable,
        ),
      ]);

      await _pumpTall(tester, document);

      // The always-visible confidence legend (§3 scope) contributes one
      // occurrence of each word on its own; requiring >= 2 here proves
      // each card ALSO carries its own badge, not just the legend.
      expect(find.text('High confidence'), findsAtLeastNWidgets(2));
      expect(find.text('Medium confidence'), findsAtLeastNWidgets(2));
      expect(find.text('Uncertain measurement'), findsAtLeastNWidgets(2));
      expect(find.text('Not applicable for this recording'), findsOneWidget);
    },
  );

  test('the presentation formatter never collapses a missing value into a '
      'numeric zero', () {
    const labels = _RecordingLabels();
    final card = OverviewViewModel.from(
      _document(<AnalysisMetricResult>[
        _metric(
          AnalysisMetricId.timingMeanAbsoluteError,
          CapabilityStatus.unavailable,
          unavailableReason: CapabilityUnavailableReason.clipTooShort,
        ),
      ]),
      labels: labels,
    );
    final unavailableCard = card.details.single;
    expect(unavailableCard.valueText, isNot('0'));
    expect(unavailableCard.valueText, 'unavailable-placeholder');
    expect(unavailableCard.state, OverviewMetricCardState.unavailable);
  });
}

/// Minimal [OverviewLabels] that returns tagged sentinel strings — used only
/// to prove the formatter branch taken, not to exercise real localisation
/// (that is covered by the widget-pumping cells above).
final class _RecordingLabels implements OverviewLabels {
  const _RecordingLabels();

  @override
  String actionDisabledTooltip(AnalysisRecommendedAction action) => 'tooltip';

  @override
  String actionLabel(AnalysisRecommendedAction action) => 'label';

  @override
  String completionLabel(AnalysisCompletion completion) => 'completion';

  @override
  String confidenceHigh() => 'high';

  @override
  String confidenceLow() => 'low';

  @override
  String confidenceMedium() => 'medium';

  @override
  String formatDbfs(double dbfs) => '$dbfs dB';

  @override
  String formatDuration(Duration duration) => '${duration.inSeconds}s';

  @override
  String formatMetricValue(AnalysisMetricResult metric) => 'value';

  @override
  String formatRatio(double ratio) => '$ratio';

  @override
  String insightKindLabel(AnalysisInsightKind kind) => 'kind-label';

  @override
  String insightKindTitle(AnalysisInsightKind kind) => 'kind-title';

  @override
  String insightMessage(String messageKey, Map<String, String> args) =>
      messageKey;

  @override
  String inputSubtitle(AnalysisInputSummary input) => 'subtitle';

  @override
  String metricLabel(String metricId) => metricId;

  @override
  String notApplicableStatusLabel() => 'not-applicable';

  @override
  String notApplicableValuePlaceholder() => 'not-applicable-placeholder';

  @override
  String overviewTitle(AnalysisDocument document) => 'title';

  @override
  String unavailableReason(CapabilityUnavailableReason reason) => 'reason';

  @override
  String unavailableStatusLabel() => 'unavailable';

  @override
  String unavailableTip(CapabilityUnavailableReason reason) => 'tip';

  @override
  String unavailableValuePlaceholder() => 'unavailable-placeholder';

  @override
  String warningHeadline(AnalysisWarning warning) => 'warning';
}
