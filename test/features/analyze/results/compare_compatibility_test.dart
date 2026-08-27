// A6-A7 (SDD Ch13 Kör 27, ADR 0246, ADR 0286 §5): the comparison screen
// states the REAL [CompatibilityEvaluator] verdict and reason — it never
// invents its own compatibility rule (§0.0/B/B6 horgony: "a UI a domain
// verdiktjét mondja ki"). Every cell runs the actual engine function to
// produce the [MetricComparison]/[AnalysisComparison] it then pumps into
// the real [AnalysisCompareScreen], asserting on the rendered TEXT
// (§0.0/B/B7).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric_catalog.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_provenance.dart';
import 'package:strumsight/features/audio_analysis/domain/comparison/analysis_comparison.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/engine/comparison/compatibility_evaluator.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_compare_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

AnalysisMetricResult _metric({
  String id = AnalysisMetricId.timingTargetMeanAbsoluteError,
  int version = 1,
  double value = 40,
  int sampleCount = 12,
}) => AnalysisMetricResult(
  id: id,
  version: version,
  status: CapabilityStatus.available,
  confidence: .8,
  unit: 'ms',
  sampleCount: sampleCount,
  evidence: const <String>[],
  value: ScalarMetricValue(value),
);

SignalQualityReport _quality({
  double overall = 0.9,
  double noiseFloorDbfs = -60,
  double clippedSampleRatio = 0,
}) => SignalQualityReport(
  overall: overall,
  peakDbfs: -3,
  rmsDbfs: -18,
  noiseFloorDbfs: noiseFloorDbfs,
  clippedSampleRatio: clippedSampleRatio,
  silentRatio: 0,
  tonalness: 0,
);

AnalysisProvenance _provenance({String? targetVersion}) => AnalysisProvenance(
  appVersion: '1',
  analyzerVersion: '1',
  pipelineVersion: '1',
  stageVersions: const <String, String>{},
  dspConfigHash: 'x',
  modelManifestIds: const <String>[],
  inputFingerprint: 'f',
  platform: 'test',
  featureFlagSnapshot: const <String, bool>{},
  targetVersion: targetVersion,
);

Widget _harness(AnalysisComparison comparison) => MaterialApp(
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: AnalysisCompareScreen(comparison: comparison),
);

void main() {
  group(
    'A6 — compatible data gets a real direction, never a fabricated one',
    () {
      testWidgets(
        'same target, same quality, same metric: the REAL engine resolves '
        '"Improved" and the screen states it with the real delta',
        (tester) async {
          final comparison = CompatibilityEvaluator.compare(
            before: _metric(value: 40),
            after: _metric(value: 30),
            beforeQuality: _quality(),
            afterQuality: _quality(),
            beforeProvenance: _provenance(targetVersion: 'song-a'),
            afterProvenance: _provenance(targetVersion: 'song-a'),
          );
          expect(comparison.direction, MetricComparisonDirection.improved);
          expect(comparison.isInconclusive, isFalse);

          await tester.pumpWidget(
            _harness(
              AnalysisComparison(
                beforeAnalysisId: 'before',
                afterAnalysisId: 'after',
                metrics: <MetricComparison>[comparison],
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Improved'), findsOneWidget);
          expect(find.textContaining('40.00'), findsOneWidget);
          expect(find.textContaining('30.00'), findsOneWidget);
          expect(find.textContaining('-10.00'), findsOneWidget);
          expect(find.textContaining('too much'), findsNothing);
        },
      );
    },
  );

  group('A6/A7 — incompatible data never starts a comparison, and states '
      'why', () {
    testWidgets(
      'different practice target: real engine verdict is inconclusive, '
      'screen shows the exact reason and no fabricated delta',
      (tester) async {
        final comparison = CompatibilityEvaluator.compare(
          before: _metric(value: 40),
          after: _metric(value: 30),
          beforeQuality: _quality(),
          afterQuality: _quality(),
          beforeProvenance: _provenance(targetVersion: 'song-a'),
          afterProvenance: _provenance(targetVersion: 'song-b'),
        );
        expect(comparison.direction, MetricComparisonDirection.inconclusive);
        expect(
          comparison.inconclusiveReason,
          ComparisonInconclusiveReason.differentTarget,
        );
        expect(comparison.beforeValue, isNull);
        expect(comparison.afterValue, isNull);

        await tester.pumpWidget(
          _harness(
            AnalysisComparison(
              beforeAnalysisId: 'before',
              afterAnalysisId: 'after',
              metrics: <MetricComparison>[comparison],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Inconclusive'), findsOneWidget);
        expect(
          find.text('The two sessions used different practice targets.'),
          findsOneWidget,
        );
        expect(find.textContaining('40.00'), findsNothing);
        expect(find.textContaining('-10.00'), findsNothing);
      },
    );

    testWidgets('diverged input quality (noise floor gap > 10 dB): real engine '
        'verdict is inconclusive, screen states that exact reason', (
      tester,
    ) async {
      final comparison = CompatibilityEvaluator.compare(
        before: _metric(value: 40),
        after: _metric(value: 30),
        beforeQuality: _quality(noiseFloorDbfs: -60),
        afterQuality: _quality(noiseFloorDbfs: -40),
        beforeProvenance: _provenance(targetVersion: 'song-a'),
        afterProvenance: _provenance(targetVersion: 'song-a'),
      );
      expect(comparison.direction, MetricComparisonDirection.inconclusive);
      expect(
        comparison.inconclusiveReason,
        ComparisonInconclusiveReason.inputQualityDiverged,
      );

      await tester.pumpWidget(
        _harness(
          AnalysisComparison(
            beforeAnalysisId: 'before',
            afterAnalysisId: 'after',
            metrics: <MetricComparison>[comparison],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inconclusive'), findsOneWidget);
      expect(
        find.text(
          'The recording quality differs too much between the two '
          'sessions.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'different metric version (real compareMetricIdentity verdict): the '
      'screen states that exact reason',
      (tester) async {
        final reason = CompatibilityEvaluator.compareMetricIdentity(
          idA: 'timing.target_mean_absolute_error.v1',
          versionA: 1,
          idB: 'timing.target_mean_absolute_error.v1',
          versionB: 2,
        );
        expect(reason, ComparisonInconclusiveReason.differentMetricVersion);

        final comparison = MetricComparison(
          metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
          direction: MetricComparisonDirection.inconclusive,
          confidence: .8,
          sampleCount: 12,
          inconclusiveReason: reason,
        );

        await tester.pumpWidget(
          _harness(
            AnalysisComparison(
              beforeAnalysisId: 'before',
              afterAnalysisId: 'after',
              metrics: <MetricComparison>[comparison],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Inconclusive'), findsOneWidget);
        expect(
          find.text(
            'The metric definition changed between the two '
            'sessions.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
