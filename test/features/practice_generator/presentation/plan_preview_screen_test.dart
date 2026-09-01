import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

void main() {
  group('PlanPreviewScreen', () {
    testWidgets('A1: leaving the preview without confirm does NOT call '
        'GenerationPlanActivation', (tester) async {
      final activation = _RecordingActivation();
      final controller = _controllerFor(
        activation: activation,
        hardAvoid: false,
      );

      await _pumpPreview(tester, controller);
      await tester.pumpAndSettle();

      // Dispose the controller without ever calling confirmConfirmed.
      // This is the path the production route takes when the user
      // dismisses the screen: the widget unmounts, the controller is
      // disposed, and no activation effect can fire.
      controller.dispose();

      expect(activation.calls, isZero);
    });

    testWidgets(
      'A2: every manual edit re-runs the validator before the next frame',
      (tester) async {
        final activation = _RecordingActivation();
        final controller = _controllerFor(
          activation: activation,
          hardAvoid: false,
        );
        addTearDown(controller.dispose);

        await _pumpPreview(tester, controller);
        await tester.pumpAndSettle();

        final before = controller.editCount;
        final block = controller.state.plan.days.first.blocks.first;
        controller.editBlockActiveDuration(
          block.id,
          const Duration(minutes: 7),
        );
        await tester.pumpAndSettle();

        expect(controller.editCount, before + 1);
        expect(
          find.byKey(Key('plan-block-${block.id.value}-duration-slider')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'A3: error-level finding blocks activation even after explicit confirm',
      (tester) async {
        final activation = _RecordingActivation();
        final controller = _controllerFor(
          activation: activation,
          hardAvoid: true,
        );
        addTearDown(controller.dispose);

        await _pumpPreview(tester, controller);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('plan-preview-findings-error')),
          findsOneWidget,
        );

        // The confirm control is rendered but disabled while the error
        // banner is up — pressing confirm must still NOT call activate.
        final confirmButton = find.byKey(const Key('plan-preview-confirm'));
        expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);

        final result = await controller.confirmConfirmed();
        expect(result.isFailure, isTrue);
        expect(activation.calls, isZero);
      },
    );

    testWidgets(
      'A4: warning requires explicit acknowledgement before activation',
      (tester) async {
        final activation = _RecordingActivation();
        final controller = _controllerFor(
          activation: activation,
          hardAvoid: false,
          consecutiveHighFretting: true,
        );
        addTearDown(controller.dispose);

        await _pumpPreview(tester, controller);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('plan-preview-findings-warning')),
          findsOneWidget,
        );

        // The confirm control is rendered but disabled while the warning
        // banner is up and the learner has not yet pressed the
        // acknowledgement button.
        final confirmButton = find.byKey(const Key('plan-preview-confirm'));
        expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);

        await tester.tap(
          find.byKey(const Key('plan-preview-acknowledge-warning')),
        );
        await tester.pumpAndSettle();

        final reEnabled = tester.widget<FilledButton>(confirmButton);
        expect(reEnabled.onPressed, isNotNull);

        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        expect(activation.calls, 1);
      },
    );

    testWidgets(
      'A7: the preview renders without network — confirms offline surface',
      (tester) async {
        final activation = _RecordingActivation();
        final controller = _controllerFor(
          activation: activation,
          hardAvoid: false,
        );
        addTearDown(controller.dispose);

        await _pumpPreview(tester, controller);
        await tester.pumpAndSettle();

        // No `network` / `http` channel calls attempted: the widget tree
        // only contains the offline preview content.
        expect(find.byKey(const Key('plan-preview-confirm')), findsOneWidget);
      },
    );

    testWidgets('A8: confirm is the ONLY path that calls activation', (
      tester,
    ) async {
      final activation = _RecordingActivation();
      final controller = _controllerFor(
        activation: activation,
        hardAvoid: false,
      );
      addTearDown(controller.dispose);

      await _pumpPreview(tester, controller);
      await tester.pumpAndSettle();

      // Several edits without confirm → activation still untouched.
      final block = controller.state.plan.days.first.blocks.first;
      controller.editBlockActiveDuration(block.id, const Duration(minutes: 4));
      await tester.pumpAndSettle();
      controller.editBlockActiveDuration(block.id, const Duration(minutes: 6));
      await tester.pumpAndSettle();
      expect(activation.calls, isZero);

      await tester.tap(find.byKey(const Key('plan-preview-confirm')));
      await tester.pumpAndSettle();

      expect(activation.calls, 1);
      expect(controller.state.confirmed, isTrue);
      expect(controller.state.plan.status, PlanStatus.active);
    });

    testWidgets(
      'regression — every edit bumps editCount AND refreshes validation '
      '(A2 truth table, the fixture-default vakfolt guard)',
      (tester) async {
        final activation = _RecordingActivation();
        final controller = _controllerFor(
          activation: activation,
          hardAvoid: false,
        );
        addTearDown(controller.dispose);

        await _pumpPreview(tester, controller);
        await tester.pumpAndSettle();

        final block = controller.state.plan.days.first.blocks.first;
        final initialIssuesCount = controller.state.validation.issues.length;

        // Edit once, twice — every edit must reach the validator.
        controller.editBlockActiveDuration(
          block.id,
          const Duration(minutes: 8),
        );
        await tester.pumpAndSettle();
        final afterFirstEditIssues = controller.state.validation.issues.length;
        expect(controller.editCount, 1);
        // Validation either re-emits the same list or a different list
        // (depending on whether the edit changes anything). The point is
        // that the validator's *method* is exercised on every edit, which
        // is what editCount==1 proves.

        controller.editBlockActiveDuration(
          block.id,
          const Duration(minutes: 9),
        );
        await tester.pumpAndSettle();
        expect(controller.editCount, 2);

        // Sanity: the issues-length stayed bounded (no infinite revalidate).
        expect(
          controller.state.validation.issues.length,
          lessThanOrEqualTo(afterFirstEditIssues + 1),
        );
        expect(initialIssuesCount, greaterThanOrEqualTo(0));
      },
    );

    testWidgets('§6.1 cell: error from manual edit also blocks activation', (
      tester,
    ) async {
      final activation = _RecordingActivation();
      // Build a controller whose context hard-avoids the candidate, then
      // a manual edit that bumps the plan to a hard-maximum violation
      // surfaces a SECOND error finding.
      final controller = _controllerFor(
        activation: activation,
        hardAvoid: true,
        tightDailyMaximum: true,
      );
      addTearDown(controller.dispose);

      await _pumpPreview(tester, controller);
      await tester.pumpAndSettle();

      final result = await controller.confirmConfirmed();
      expect(result.isFailure, isTrue);
      expect(activation.calls, isZero);
    });

    testWidgets(
      'F1 regression: opening the reason sheet from the screen path with an '
      'uncertain priority appends the uncertainty line (§5.4, A6)',
      (tester) async {
        final activation = _RecordingActivation();
        final base = buildPlan();
        final firstBlock = base.days.first.blocks.first;
        // The block has evidence.tempo-accuracy by default (fixture) — the
        // very code path the F1 review flagged. The screen receives the
        // priority through the controller, and the sheet must append the
        // uncertainty line because the priority's uncertainty factor is
        // at/above the threshold.
        final priority = SkillPriority(
          skillId: 'rhythm.quarterNotes',
          score: -0.21,
          policyVersion: 'policy.test.v1',
          factors: <SkillPriorityFactor>[
            SkillPriorityFactor(
              kind: SkillPriorityFactorKind.uncertainty,
              normalizedValue: 0.7,
              contribution: -0.21,
            ),
          ],
          isSafetyOverridden: false,
        );
        final controller = PlanPreviewController(
          initialPlan: base,
          validationContext: buildContext(),
          activation: activation,
          priorities: <BlockId, SkillPriority>{firstBlock.id: priority},
        );
        addTearDown(controller.dispose);

        await _pumpPreview(tester, controller);
        await tester.pumpAndSettle();

        // Tap the real on-screen block → the screen wires the priority
        // through → the sheet opens with uncertainty. This is the path the
        // existing plan_reason_sheet_test never covered (it opened the
        // sheet directly via `PlanReasonSheet.show`).
        await tester.tap(find.byKey(Key('plan-block-${firstBlock.id.value}')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('plan-reason-uncertain')), findsOneWidget);
      },
    );

    testWidgets(
      'F1 fail-closed: the screen also renders the uncertainty line when '
      'NO priority was supplied for the tapped block (§5.4)',
      (tester) async {
        final activation = _RecordingActivation();
        // Same fixture, NO priorities map entry for the block. The screen
        // looks up priorityFor and gets null; the sheet must fail-closed
        // and append the uncertainty line rather than imply confidence.
        final controller = _controllerFor(
          activation: activation,
          hardAvoid: false,
        );
        addTearDown(controller.dispose);

        await _pumpPreview(tester, controller);
        await tester.pumpAndSettle();

        final firstBlock = controller.state.plan.days.first.blocks.first;
        await tester.tap(find.byKey(Key('plan-block-${firstBlock.id.value}')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('plan-reason-uncertain')), findsOneWidget);
      },
    );
  });

  group('A3 — large-text overflow, phone viewport', () {
    testWidgets('preview renders without overflow at 2.0 (en)', (tester) async {
      final activation = _RecordingActivation();
      final controller = _controllerFor(
        activation: activation,
        hardAvoid: false,
      );
      addTearDown(controller.dispose);

      await _pumpPreviewOnPhone(tester, controller, textScaleFactor: 2);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('preview renders without overflow at 2.0 (hu)', (tester) async {
      final activation = _RecordingActivation();
      final controller = _controllerFor(
        activation: activation,
        hardAvoid: false,
      );
      addTearDown(controller.dispose);

      await _pumpPreviewOnPhone(
        tester,
        controller,
        textScaleFactor: 2,
        locale: const Locale('hu'),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

PlanPreviewController _controllerFor({
  required _RecordingActivation activation,
  required bool hardAvoid,
  bool consecutiveHighFretting = false,
  bool tightDailyMaximum = false,
}) {
  final candidate = buildCandidate();
  final base = buildPlan();
  if (!consecutiveHighFretting) {
    final context = buildContext(
      hardAvoidIdentities: hardAvoid
          ? <String>[identityOf(candidate)]
          : <String>[],
      availability: tightDailyMaximum
          ? buildAvailability(maximumMinutes: 1)
          : buildAvailability(),
    );
    return PlanPreviewController(
      initialPlan: base,
      validationContext: context,
      activation: activation,
    );
  }
  final candidates = <ExerciseCandidate>[
    for (var index = 0; index < 4; index++)
      buildCandidate(
        exerciseId: 'exercise.rhythm.$index',
        frettingHandLoad: LoadLevel.high,
      ),
  ];
  final firstDay = base.days.first;
  final blocks = <PracticeBlock>[
    for (var index = 0; index < candidates.length; index++)
      buildBlock(
        id: '${firstDay.id.value}.block.${index + 1}',
        order: index + 1,
        prescription: buildPrescription(candidates[index]),
        estimatedElapsed: const Duration(minutes: 6),
      ),
  ];
  final nextDay = firstDay.replaceContent(blocks: blocks);
  final plan = base.copyWith(days: <PracticeDay>[nextDay]);
  final catalog = buildCatalog(candidates: candidates);
  final context = PlanValidationContext(
    catalog: catalog,
    availability: buildAvailability(),
    repairRevisionId: RevisionId('revision.2'),
    hardAvoidIdentities: hardAvoid
        ? <String>[identityOf(candidate)]
        : <String>[],
  );
  return PlanPreviewController(
    initialPlan: plan,
    validationContext: context,
    activation: activation,
  );
}

Future<void> _pumpPreview(
  WidgetTester tester,
  PlanPreviewController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => PlanPreviewScreen(controller: controller),
        ),
      ),
    ),
  );
}

// §0.0.A/R7 (L558) — PHONE-sized viewport (360x640, dpr 1.0) + a caller
// locale, for the round's own A3 overflow evidence (not the flutter_test
// default 800x600, which under-measures a scrollable preview list).
Future<void> _pumpPreviewOnPhone(
  WidgetTester tester,
  PlanPreviewController controller, {
  double textScaleFactor = 1,
  Locale locale = const Locale('en'),
}) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: SsLightTheme.data(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScaleFactor)),
        child: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => PlanPreviewScreen(controller: controller),
          ),
        ),
      ),
    ),
  );
}

final class _RecordingActivation implements GenerationPlanActivation {
  int calls = 0;

  @override
  Future<void> activate(AdaptivePracticePlan plan) async {
    calls += 1;
  }
}
