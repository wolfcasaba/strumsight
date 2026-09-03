// SDD Ch13 Kör 26 — processing Stage (ADR 0285).
//
// Covers A3 (the three progress tiers — indeterminate, phase-level,
// percentage — never a synthetic number), A4 (cancellation is idempotent
// per run, not disabled forever) and A8 (a degraded completion names the
// MEASURED CapabilityUnavailableReason, never an invented heat/battery
// excuse).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_processing_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/widgets/labels_adapter.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester, Widget home) => tester.pumpWidget(
  MaterialApp(
    theme: SsLightTheme.data(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

BuildContext _context(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).first);

void main() {
  group('AnalysisProcessingScreen — A3 no fake percent', () {
    testWidgets('below the threshold: an indeterminate signal, no number', (
      tester,
    ) async {
      await _pump(
        tester,
        AnalysisProcessingScreen(
          state: const AnalysisAnalyzing(runId: 'run-1'),
          onCancel: () {},
        ),
      );

      expect(
        find.byKey(const Key('analysis-processing-starting-bar')),
        findsOneWidget,
      );
      expect(find.textContaining('%'), findsNothing);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('analysis-processing-starting-bar')),
      );
      expect(bar.value, isNull);
    });

    testWidgets('on the threshold: a real phase-level signal, no number', (
      tester,
    ) async {
      await _pump(
        tester,
        AnalysisProcessingScreen(
          state: const AnalysisAnalyzing(
            runId: 'run-1',
            phase: AnalysisProgressPhase.estimatingHarmony,
          ),
          onCancel: () {},
        ),
      );

      final expectedIndex =
          AnalysisProgressPhase.values.indexOf(
            AnalysisProgressPhase.estimatingHarmony,
          ) +
          1;
      final expectedTotal = AnalysisProgressPhase.values.length;
      expect(
        find.text(
          AppLocalizations.of(
            _context(tester),
          ).analysisProcessingStepIndicator(expectedIndex, expectedTotal),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('%'), findsNothing);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNull);
    });

    testWidgets('above the threshold: the actual percentage', (tester) async {
      await _pump(
        tester,
        AnalysisProcessingScreen(
          state: const AnalysisAnalyzing(
            runId: 'run-1',
            phase: AnalysisProgressPhase.computingMetrics,
            completedUnits: 3,
            totalUnits: 5,
          ),
          onCancel: () {},
        ),
      );

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.6, 1e-9));
    });
  });

  group('AnalysisProcessingScreen — A4 idempotent cancel', () {
    testWidgets('a second tap on the same run does not cancel twice', (
      tester,
    ) async {
      var cancelCalls = 0;
      await _pump(
        tester,
        AnalysisProcessingScreen(
          state: const AnalysisAnalyzing(
            runId: 'run-1',
            phase: AnalysisProgressPhase.preprocessing,
          ),
          onCancel: () => cancelCalls++,
        ),
      );

      final cancelButton = find.bySemanticsLabel('Cancel analysis');
      await tester.tap(cancelButton);
      await tester.pump();
      await tester.tap(cancelButton);
      await tester.pump();

      expect(cancelCalls, 1);
    });

    testWidgets('a later, different run can be cancelled again', (
      tester,
    ) async {
      var cancelCalls = 0;
      await _pump(
        tester,
        AnalysisProcessingScreen(
          state: const AnalysisAnalyzing(
            runId: 'run-1',
            phase: AnalysisProgressPhase.preprocessing,
          ),
          onCancel: () => cancelCalls++,
        ),
      );
      final cancelButton = find.bySemanticsLabel('Cancel analysis');
      await tester.tap(cancelButton);
      await tester.tap(cancelButton);
      await tester.pump();
      expect(cancelCalls, 1);

      await _pump(
        tester,
        AnalysisProcessingScreen(
          state: const AnalysisAnalyzing(
            runId: 'run-2',
            phase: AnalysisProgressPhase.preprocessing,
          ),
          onCancel: () => cancelCalls++,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Cancel analysis'));
      await tester.pump();

      expect(cancelCalls, 2);
    });
  });

  group('AnalysisProcessingScreen — A8 measured degraded reason', () {
    testWidgets('names the measured CapabilityUnavailableReason', (
      tester,
    ) async {
      final document = _degradedDocument(
        CapabilityUnavailableReason.modelUnavailable,
      );
      await _pump(
        tester,
        AnalysisProcessingScreen(
          state: AnalysisDegradedCompleted(runId: 'run-1', document: document),
          onCancel: () {},
        ),
      );

      final l10n = AppLocalizations.of(_context(tester));
      final labels = AppLocalizationsOverviewLabels(l10n);
      expect(
        find.text(
          '• ${labels.unavailableReason(CapabilityUnavailableReason.modelUnavailable)}',
        ),
        findsOneWidget,
      );
      // Never a fabricated heat/battery excuse — that string does not exist
      // anywhere in the generated localizations for this screen.
      expect(find.textContaining('heat'), findsNothing);
      expect(find.textContaining('battery'), findsNothing);
    });
  });

  group('§0.0.A/R12 — input/general failures render SsFailureState', () {
    testWidgets(
      'AnalysisInputError (non-retryable) shows the failure state with a real action',
      (tester) async {
        await _pump(
          tester,
          AnalysisProcessingScreen(
            state: const AnalysisInputError(
              ValidationFailure(code: 'validation.input'),
            ),
            onCancel: () {},
            onRestart: () {},
          ),
        );
        expect(find.byType(SsFailureState), findsOneWidget);
        // B1 — a non-retryable failure must not leave the user with zero
        // actionable buttons: the restart affordance stays reachable.
        expect(
          find.byKey(const Key('analysis-processing-restart')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'AnalysisError (retryable) shows the failure state with a real action',
      (tester) async {
        await _pump(
          tester,
          AnalysisProcessingScreen(
            state: const AnalysisError(runId: 'run-1', failure: AudioFailure()),
            onCancel: () {},
            onRestart: () {},
          ),
        );
        expect(find.byType(SsFailureState), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
      },
    );

    testWidgets(
      'AnalysisError (non-retryable) shows the failure state with a real action',
      (tester) async {
        await _pump(
          tester,
          AnalysisProcessingScreen(
            state: const AnalysisError(
              runId: 'run-1',
              failure: UnknownFailure(),
            ),
            onCancel: () {},
            onRestart: () {},
          ),
        );
        expect(find.byType(SsFailureState), findsOneWidget);
        expect(
          find.byKey(const Key('analysis-processing-restart')),
          findsOneWidget,
        );
      },
    );
  });

  group('§0.0.A/R11 — textScaler 2.0, en/hu, no overflow', () {
    for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
      testWidgets('AnalysisProcessingScreen — ${locale.languageCode}', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(
            theme: SsLightTheme.data(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AnalysisProcessingScreen(
              state: const AnalysisAnalyzing(
                runId: 'run-1',
                phase: AnalysisProgressPhase.computingMetrics,
                completedUnits: 3,
                totalUnits: 5,
              ),
              onCancel: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

AnalysisDocument _degradedDocument(CapabilityUnavailableReason reason) =>
    AnalysisDocument(
      id: 'analysis-degraded',
      schemaVersion: analysisDocumentSchemaVersion,
      createdAt: DateTime.utc(2026),
      mode: AnalysisMode.freePlay,
      input: AnalysisInputSummary(
        source: AnalysisInputSource.microphone,
        duration: const Duration(seconds: 1),
        sampleRate: 44100,
        channelCount: 1,
        fingerprint: 'fingerprint',
      ),
      provenance: AnalysisProvenance(
        appVersion: '1.0.0',
        analyzerVersion: '1',
        pipelineVersion: '1',
        stageVersions: const <String, String>{'signal': '1'},
        dspConfigHash: 'hash',
        modelManifestIds: const <String>[],
        inputFingerprint: 'fingerprint',
        platform: 'android',
        featureFlagSnapshot: const <String, bool>{},
      ),
      signalQuality: SignalQualityReport(
        overall: 0.5,
        peakDbfs: -1,
        rmsDbfs: -12,
        noiseFloorDbfs: -48,
        clippedSampleRatio: 0,
        silentRatio: 0,
        tonalness: 0.5,
      ),
      capabilities: <CapabilityReport>[
        CapabilityReport(
          capability: AnalysisCapability.chordTimeline,
          status: CapabilityStatus.unavailable,
          confidence: 0,
          reason: reason,
        ),
      ],
      timeline: AnalysisTimeline(duration: const Duration(seconds: 1)),
      metrics: const <AnalysisMetricResult>[],
      hotspots: const <AnalysisHotspot>[],
      insights: const <AnalysisInsight>[],
      warnings: const <AnalysisWarning>[],
      completion: AnalysisCompletion(status: AnalysisCompletionStatus.degraded),
    );
