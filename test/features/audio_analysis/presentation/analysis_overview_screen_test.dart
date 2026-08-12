import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:strumsight/features/audio_analysis/presentation/analysis_overview_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

AnalysisDocument _document({
  List<AnalysisMetricResult> metrics = const <AnalysisMetricResult>[],
  List<AnalysisInsight> insights = const <AnalysisInsight>[],
}) {
  return AnalysisDocument(
    id: 'overview-doc',
    schemaVersion: analysisDocumentSchemaVersion,
    createdAt: DateTime.utc(2026, 8, 12),
    mode: AnalysisMode.freePlay,
    input: AnalysisInputSummary(
      source: AnalysisInputSource.microphone,
      duration: const Duration(minutes: 2, seconds: 5),
      sampleRate: 48000,
      channelCount: 1,
      fingerprint: 'fp-overview',
    ),
    provenance: AnalysisProvenance(
      appVersion: '1.0.0',
      analyzerVersion: '1',
      pipelineVersion: '1',
      stageVersions: const <String, String>{},
      dspConfigHash: 'cfg',
      modelManifestIds: const <String>[],
      inputFingerprint: 'fp-overview',
      platform: 'android',
      featureFlagSnapshot: const <String, bool>{},
    ),
    signalQuality: SignalQualityReport(
      overall: 0,
      peakDbfs: -3,
      rmsDbfs: -18,
      noiseFloorDbfs: -60,
      clippedSampleRatio: 0,
      silentRatio: 0,
      tonalness: 0,
    ),
    capabilities: const <CapabilityReport>[],
    timeline: AnalysisTimeline(
      duration: const Duration(minutes: 2, seconds: 5),
    ),
    metrics: metrics,
    hotspots: const [],
    insights: insights,
    warnings: const <AnalysisWarning>[],
    completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
  );
}

AnalysisMetricResult _metric(
  String id,
  CapabilityStatus status, {
  AnalysisMetricValue? value,
  CapabilityUnavailableReason? unavailableReason,
  String unit = 'ms',
}) {
  return AnalysisMetricResult(
    id: id,
    version: 1,
    status: status,
    confidence: 0.8,
    unit: unit,
    sampleCount: 10,
    evidence: const <String>[],
    value: value,
    unavailableReason: unavailableReason,
  );
}

Widget _harness(
  AnalysisDocument document, {
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: AnalysisOverviewScreen(document: document),
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

void main() {
  group('AnalysisOverviewScreen', () {
    testWidgets('shows empty state when document is missing without crashing', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const MaterialApp(
          localizationsDelegates: <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: AnalysisOverviewScreen(),
        ),
        size: const Size(400, 800),
      );
      expect(find.text('Analysis overview'), findsOneWidget);
      expect(
        find.text('No analysis document is available yet.'),
        findsOneWidget,
      );
    });

    testWidgets('renders complete document with primary metrics and insights', (
      tester,
    ) async {
      final document = _document(
        metrics: <AnalysisMetricResult>[
          _metric(
            AnalysisMetricId.timingMeanAbsoluteError,
            CapabilityStatus.available,
            value: ScalarMetricValue(0.05),
            unit: 's',
          ),
          _metric(
            AnalysisMetricId.rhythmRushDragBias,
            CapabilityStatus.degraded,
            value: ScalarMetricValue(0.01),
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
      );

      await _pumpAt(tester, _harness(document), size: const Size(400, 1200));
      expect(find.text('Analysis overview'), findsOneWidget);
      expect(find.text('Main metrics'), findsOneWidget);
      expect(find.byType(Card), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'locale parity — english and hungarian render translated text',
      (tester) async {
        final document = _document(
          metrics: <AnalysisMetricResult>[
            _metric(
              AnalysisMetricId.timingMeanAbsoluteError,
              CapabilityStatus.available,
              value: ScalarMetricValue(0.05),
              unit: 's',
            ),
          ],
        );

        await _pumpAt(
          tester,
          _harness(document, locale: const Locale('en')),
          size: const Size(400, 1200),
        );
        expect(find.text('Analysis overview'), findsOneWidget);
        expect(find.text('Main metrics'), findsOneWidget);

        await _pumpAt(
          tester,
          _harness(document, locale: const Locale('hu')),
          size: const Size(400, 1200),
        );
        expect(find.text('Elemzés áttekintése'), findsOneWidget);
        expect(find.text('Fő metrikák'), findsOneWidget);
      },
    );

    testWidgets(
      'overflow matrix — 320px / 2.0 scale renders without overflow',
      (tester) async {
        final document = _document(
          metrics: <AnalysisMetricResult>[
            _metric(
              AnalysisMetricId.timingMeanAbsoluteError,
              CapabilityStatus.available,
              value: ScalarMetricValue(0.05),
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
              unavailableReason: CapabilityUnavailableReason.inputTooNoisy,
            ),
            _metric(
              AnalysisMetricId.harmonyChordCoverage,
              CapabilityStatus.unavailable,
              unavailableReason: CapabilityUnavailableReason.confidenceTooLow,
            ),
          ],
        );

        await _pumpAt(
          tester,
          _harness(document),
          size: const Size(320, 800),
          textScale: 2.0,
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'overflow matrix — 600px / 1.0 scale renders without overflow',
      (tester) async {
        final document = _document(
          metrics: <AnalysisMetricResult>[
            _metric(
              AnalysisMetricId.timingMeanAbsoluteError,
              CapabilityStatus.available,
              value: ScalarMetricValue(0.05),
              unit: 's',
            ),
          ],
        );

        await _pumpAt(
          tester,
          _harness(document),
          size: const Size(600, 1200),
          textScale: 1.0,
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'four-document matrix — full, degraded, all-unavailable, silent '
      '— renders without overflow',
      (tester) async {
        Future<void> pumpWith(List<AnalysisMetricResult> metrics) async {
          await _pumpAt(
            tester,
            _harness(_document(metrics: metrics)),
            size: const Size(400, 1400),
          );
          expect(tester.takeException(), isNull);
        }

        await pumpWith(<AnalysisMetricResult>[
          _metric(
            AnalysisMetricId.timingMeanAbsoluteError,
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
            value: ScalarMetricValue(0.2),
          ),
          _metric(
            AnalysisMetricId.harmonyChordCoverage,
            CapabilityStatus.available,
            value: ScalarMetricValue(0.95),
          ),
        ]);

        await pumpWith(<AnalysisMetricResult>[
          _metric(
            AnalysisMetricId.timingMeanAbsoluteError,
            CapabilityStatus.degraded,
            value: ScalarMetricValue(0.08),
            unit: 's',
          ),
        ]);

        await pumpWith(<AnalysisMetricResult>[
          _metric(
            AnalysisMetricId.timingMeanAbsoluteError,
            CapabilityStatus.unavailable,
            unavailableReason: CapabilityUnavailableReason.clipTooShort,
          ),
          _metric(
            AnalysisMetricId.rhythmRushDragBias,
            CapabilityStatus.unavailable,
            unavailableReason: CapabilityUnavailableReason.inputTooNoisy,
          ),
        ]);

        await pumpWith(<AnalysisMetricResult>[]);
      },
    );

    testWidgets(
      'maximum-policy — 9 insights still show only the four primary slots',
      (tester) async {
        final many = <AnalysisInsight>[];
        for (var i = 0; i < 9; i++) {
          many.add(
            AnalysisInsight(
              id: 'i-$i',
              ruleId: 'r-$i',
              ruleVersion: '1',
              priority: i < 3
                  ? AnalysisInsightPriority.high
                  : AnalysisInsightPriority.medium,
              kind: i % 3 == 0
                  ? AnalysisInsightKind.recommendation
                  : (i % 3 == 1
                        ? AnalysisInsightKind.observation
                        : AnalysisInsightKind.caution),
              factIds: const <String>[],
              messageKey: 'analysisInsightRushBias',
              messageArgs: <String, String>{'milliseconds': '$i'},
              recommendedAction: AnalysisRecommendedAction.continuePractice,
            ),
          );
        }
        await _pumpAt(
          tester,
          _harness(_document(insights: many)),
          size: const Size(400, 2400),
        );
        // The screen renders at most four insight cards (one per kind slot).
        final insightCardMatches = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'InsightCard',
        );
        expect(insightCardMatches.evaluate().length, lessThanOrEqualTo(4));
      },
    );
  });

  test('no UI threshold comparison — presentation never compares confidence '
      'against a numeric threshold', () {
    // Read the source files and assert no literal threshold comparisons.
    final files = <String>[
      'lib/features/audio_analysis/presentation/analysis_overview_screen.dart',
      'lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart',
      'lib/features/audio_analysis/presentation/controllers/overview_view_model.dart',
      'lib/features/audio_analysis/presentation/widgets/metric_card.dart',
      'lib/features/audio_analysis/presentation/widgets/insight_card.dart',
      'lib/features/audio_analysis/presentation/widgets/signal_quality_card.dart',
      'lib/features/audio_analysis/presentation/widgets/confidence_badge.dart',
      'lib/features/audio_analysis/presentation/widgets/labels_adapter.dart',
    ];
    for (final file in files) {
      final contents = File(file).readAsStringSync();
      // Confidence-threshold literals (presentation must never introduce
      // its own 0.4 / 0.7 boundaries; the domain owns them).
      final thresholdRegex = RegExp(r'confidence\s*[<>]=?\s*0\.\d');
      expect(
        thresholdRegex.hasMatch(contents),
        isFalse,
        reason: '$file must not contain a confidence threshold literal',
      );
    }
  });

  test('no engine import — presentation never imports the engine layer', () {
    final files = <String>[
      'lib/features/audio_analysis/presentation/analysis_overview_screen.dart',
      'lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart',
      'lib/features/audio_analysis/presentation/controllers/overview_view_model.dart',
      'lib/features/audio_analysis/presentation/widgets/metric_card.dart',
      'lib/features/audio_analysis/presentation/widgets/insight_card.dart',
      'lib/features/audio_analysis/presentation/widgets/signal_quality_card.dart',
      'lib/features/audio_analysis/presentation/widgets/confidence_badge.dart',
      'lib/features/audio_analysis/presentation/widgets/labels_adapter.dart',
    ];
    for (final file in files) {
      final contents = File(file).readAsStringSync();
      expect(
        contents.contains('/engine/'),
        isFalse,
        reason: '$file must not import the engine layer',
      );
    }
  });
}
