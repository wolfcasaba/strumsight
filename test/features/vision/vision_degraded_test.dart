// E13-R30 acceptance: A4 (a low-confidence result is never rendered as a
// categorical technique verdict) and A5 (thermal throttling and tracking
// loss are distinct, separately-named states — never merged into one
// message). See docs/rounds/e13-r30-vision-ui.md §6.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/vision/application/calibration_loss_machine.dart';
import 'package:strumsight/features/vision/application/vision_session_controller.dart';
import 'package:strumsight/features/vision/application/vision_session_state.dart';
import 'package:strumsight/features/vision/data/performance/thermal_state_adapter.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/performance/vision_performance_summary.dart';
import 'package:strumsight/features/vision/domain/quality/vision_quality_summary.dart';
import 'package:strumsight/features/vision/domain/vision_session.dart';
import 'package:strumsight/features/vision/domain/vision_session_result.dart';
import 'package:strumsight/features/vision/presentation/providers/vision_thermal_providers.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_result_screen.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_session_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../core/storage/in_memory_key_value_store.dart';

// R2 (§0.0): the migrated screen's SsButton/SsSwitchRow now read the
// design-system theme extensions — a themeless MaterialApp null-check
// crashes (L593-class defect).
Widget _host(Widget child, {List<Override> overrides = const <Override>[]}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

VisionSessionResult _resultWith(VisionInsight insight) => VisionSessionResult(
  session: VisionSession(
    id: VisionSessionId.create('degraded-test-session'),
    startedAt: DateTime.utc(2026, 8, 27, 12),
  ),
  endedAt: DateTime.utc(2026, 8, 27, 12, 5),
  endReason: VisionSessionEndReason.explicitStop,
  qualitySummary: VisionQualitySummary.fromFrames(const []),
  calibrationState: CalibrationLossState.tracking,
  sessionSummary: <VisionInsight>[insight],
  observedFrameCount: 120,
);

final class _SeededVisionSessionController extends VisionSessionController {
  _SeededVisionSessionController(this.initialStatus);

  final VisionSessionStatus initialStatus;

  @override
  VisionSessionState build() =>
      VisionSessionState.idle().copyWith(status: initialStatus);
}

void main() {
  group('A4 — a low-confidence result is never a categorical verdict', () {
    testWidgets('high confidence renders the categorical technique wording', (
      tester,
    ) async {
      final insight = VisionInsight(
        code: InsightCode.frettingStable,
        policyVersion: 'e05-r23-v1',
        evidenceIds: const <String>['evidence-1'],
        confidence: 0.9,
      );
      await tester.pumpWidget(
        _host(
          VisionResultScreen(
            result: _resultWith(insight),
            onStartCorrectivePractice: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(VisionResultScreen)),
      );
      expect(find.text(l10n.visionInsightFrettingStable), findsOneWidget);
      expect(find.text(l10n.visionResultLowConfidenceMetric), findsNothing);
    });

    testWidgets(
      'low confidence withholds the categorical wording for a neutral notice',
      (tester) async {
        final insight = VisionInsight(
          code: InsightCode.frettingFocus,
          policyVersion: 'e05-r23-v1',
          evidenceIds: const <String>['evidence-1'],
          confidence: 0.2,
        );
        await tester.pumpWidget(
          _host(
            VisionResultScreen(
              result: _resultWith(insight),
              onStartCorrectivePractice: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(VisionResultScreen)),
        );
        expect(find.text(l10n.visionInsightFrettingFocus), findsNothing);
        expect(find.text(l10n.visionResultLowConfidenceMetric), findsOneWidget);
      },
    );
  });

  group('A5 — thermal throttling and tracking loss are distinct states', () {
    testWidgets(
      'thermal pressure while tracking shows only the thermal banner',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const VisionSessionScreen(),
            overrides: [
              visionSessionControllerProvider.overrideWith(
                () =>
                    _SeededVisionSessionController(VisionSessionStatus.running),
              ),
              visionThermalDecisionProvider.overrideWithValue(
                const VisionThermalDecision(
                  load: 85,
                  source: VisionThermalDecisionSource.platform,
                ),
              ),
              keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(VisionSessionScreen)),
        );
        expect(
          find.byKey(const Key('vision-thermal-throttled')),
          findsOneWidget,
        );
        expect(find.text(l10n.visionSessionThermalThrottled), findsOneWidget);
        expect(find.text(l10n.visionSessionCalibrationLost), findsNothing);
      },
    );

    testWidgets(
      'tracking loss without thermal pressure shows only the calibration-lost '
      'text, never the thermal banner',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const VisionSessionScreen(),
            overrides: [
              visionSessionControllerProvider.overrideWith(
                () => _SeededVisionSessionController(
                  VisionSessionStatus.calibrationLost,
                ),
              ),
              keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(VisionSessionScreen)),
        );
        expect(find.text(l10n.visionSessionCalibrationLost), findsOneWidget);
        expect(find.byKey(const Key('vision-thermal-throttled')), findsNothing);
      },
    );

    testWidgets(
      'both at once render as two separate, distinctly worded signals',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const VisionSessionScreen(),
            overrides: [
              visionSessionControllerProvider.overrideWith(
                () => _SeededVisionSessionController(
                  VisionSessionStatus.calibrationLost,
                ),
              ),
              visionThermalDecisionProvider.overrideWithValue(
                const VisionThermalDecision(
                  load: 90,
                  source: VisionThermalDecisionSource.platform,
                ),
              ),
              keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(VisionSessionScreen)),
        );
        expect(
          find.byKey(const Key('vision-thermal-throttled')),
          findsOneWidget,
        );
        expect(find.text(l10n.visionSessionThermalThrottled), findsOneWidget);
        expect(find.text(l10n.visionSessionCalibrationLost), findsOneWidget);
      },
    );
  });
}
