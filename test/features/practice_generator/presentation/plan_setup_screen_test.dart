import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/practice_generator/data/local/generation_draft_repository.dart';
import 'package:strumsight/features/practice_generator/presentation/controller/plan_setup_controller.dart';
import 'package:strumsight/features/practice_generator/presentation/screens/plan_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

void main() {
  PlanSetupController controllerFor(
    InMemoryKeyValueStore store, {
    String locale = 'en',
  }) => PlanSetupController(
    draftRepository: GenerationDraftRepository(keyValueStore: store),
    clock: () => DateTime.utc(2026, 8, 18),
    generateId: () => 'wizard-test-id',
    locale: locale,
  );

  Future<void> pumpWizard(
    WidgetTester tester,
    PlanSetupController controller, {
    double textScaleFactor = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScaleFactor)),
        child: PlanSetupScreen(controller: controller),
      ),
    ),
  );

  // §0.0.A/R7 (L558) — PHONE-sized viewport (360x640, dpr 1.0), not the
  // flutter_test default 800x600, so the wizard's own overflow (or lack of
  // it) is measured on a real phone-shaped tree, not a wider/taller one.
  Future<void> pumpWizardOnPhone(
    WidgetTester tester,
    PlanSetupController controller, {
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
          child: PlanSetupScreen(controller: controller),
        ),
      ),
    );
  }

  Future<void> completeComfortStep(
    WidgetTester tester,
    PlanSetupController controller,
    String comfortText,
  ) async {
    await pumpWizard(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-goal-unknown')));
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();
    for (var step = 1; step < 4; step++) {
      await tester.tap(find.byKey(const Key('plan-setup-unknown')));
      await tester.tap(find.byKey(const Key('plan-setup-next')));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const Key('plan-comfort-free-text')),
      comfortText,
    );
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();
  }

  testWidgets('starts without a draft and persists each completed step', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    final controller = controllerFor(store);
    addTearDown(controller.dispose);

    await pumpWizard(tester, controller);
    await tester.pumpAndSettle();

    expect(controller.state.request, isNull);
    expect(store.values, isEmpty);

    await tester.tap(find.byKey(const Key('plan-goal-rhythm')));
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();

    expect(controller.state.currentStep, 1);
    expect(store.values, contains(GenerationDraftRepository.draftStorageKey));
    expect(controller.state.request!.goals.single.type.code, 'rhythm');
  });

  testWidgets('restores a draft at the boundary after restart', (tester) async {
    final store = InMemoryKeyValueStore();
    final first = controllerFor(store);
    addTearDown(first.dispose);
    await pumpWizard(tester, first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-goal-rhythm')));
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();

    final restored = controllerFor(store);
    addTearDown(restored.dispose);
    await pumpWizard(tester, restored);
    await tester.pumpAndSettle();

    expect(restored.state.currentStep, 1);
    expect(restored.state.request!.goals.single.type.code, 'rhythm');
  });

  testWidgets('restores the next step after an unknown availability answer', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    final first = controllerFor(store);
    addTearDown(first.dispose);
    await pumpWizard(tester, first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-goal-rhythm')));
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-setup-unknown')));
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();

    expect(first.state.currentStep, 2);

    final restored = controllerFor(store);
    addTearDown(restored.dispose);
    await pumpWizard(tester, restored);
    await tester.pumpAndSettle();

    expect(restored.state.currentStep, 2);
  });

  testWidgets('restores the next step after an unknown equipment answer', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    final first = controllerFor(store);
    addTearDown(first.dispose);
    await pumpWizard(tester, first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-goal-rhythm')));
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-setup-unknown')));
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-setup-unknown')));
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();

    expect(first.state.currentStep, 3);

    final restored = controllerFor(store);
    addTearDown(restored.dispose);
    await pumpWizard(tester, restored);
    await tester.pumpAndSettle();

    expect(restored.state.currentStep, 3);
  });

  testWidgets('back navigation retains the previously entered answer', (
    tester,
  ) async {
    final controller = controllerFor(InMemoryKeyValueStore());
    addTearDown(controller.dispose);
    await pumpWizard(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-goal-rhythm')));
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-setup-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plan-goal-rhythm')), findsOneWidget);
    expect(controller.state.request!.goals.single.type.code, 'rhythm');
  });

  testWidgets('restores a completed wizard after restart', (tester) async {
    final store = InMemoryKeyValueStore();
    final controller = controllerFor(store);
    addTearDown(controller.dispose);
    await pumpWizard(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-goal-unknown')));
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();
    for (var step = 1; step < 4; step++) {
      await tester.tap(find.byKey(const Key('plan-setup-unknown')));
      await tester.tap(find.byKey(const Key('plan-setup-next')));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const Key('plan-comfort-free-text')),
      'Needs a relaxed wrist position',
    );
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();

    final restored = controllerFor(store);
    addTearDown(restored.dispose);
    await pumpWizard(tester, restored);
    await tester.pumpAndSettle();

    expect(restored.state.currentStep, 5);
    expect(restored.state.request!.constraints.constraints, hasLength(1));
  });

  testWidgets('unknown answers are persisted as absence, never defaults (A4)', (
    tester,
  ) async {
    final controller = controllerFor(InMemoryKeyValueStore());
    addTearDown(controller.dispose);
    await pumpWizard(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-goal-unknown')));
    await tester.tap(find.byKey(const Key('plan-setup-next')));
    await tester.pumpAndSettle();

    expect(controller.state.request!.goals, isEmpty);
    expect(controller.state.request!.availability.days, isEmpty);
    expect(controller.state.request!.constraints.constraints, isEmpty);
  });

  testWidgets('shows a hard conflict on the step where it is created (A5)', (
    tester,
  ) async {
    final controller = controllerFor(InMemoryKeyValueStore());
    addTearDown(controller.dispose);
    await pumpWizard(tester, controller);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-goal-custom')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plan-setup-conflict')), findsOneWidget);
  });

  testWidgets('comfort free text is retained only in the local draft (A9)', (
    tester,
  ) async {
    final controller = controllerFor(InMemoryKeyValueStore());
    addTearDown(controller.dispose);
    await completeComfortStep(
      tester,
      controller,
      'Wrist hurts after ten minutes',
    );

    expect(
      controller.state.request!.constraints.constraints.single.value,
      'Wrist hurts after ten minutes',
    );
  });

  testWidgets('comfort free text never reaches debug output (A9)', (
    tester,
  ) async {
    const sentinel = 'comfort-sentinel-raw-text';
    final capturedDebugOutput = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) capturedDebugOutput.add(message);
    };
    try {
      final successful = controllerFor(InMemoryKeyValueStore());
      addTearDown(successful.dispose);
      await completeComfortStep(tester, successful, sentinel);

      final failedStore = InMemoryKeyValueStore()
        ..failingKeys.add(GenerationDraftRepository.draftStorageKey);
      final failed = controllerFor(failedStore);
      addTearDown(failed.dispose);
      await completeComfortStep(tester, failed, sentinel);

      expect(capturedDebugOutput.join('\n'), isNot(contains(sentinel)));
    } finally {
      debugPrint = originalDebugPrint;
    }
  });

  group('A3 — large-text overflow, phone viewport', () {
    testWidgets('goal step renders without overflow at 2.0 (en)', (
      tester,
    ) async {
      final controller = controllerFor(InMemoryKeyValueStore());
      addTearDown(controller.dispose);
      await pumpWizardOnPhone(tester, controller, textScaleFactor: 2);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('goal step renders without overflow at 2.0 (hu)', (
      tester,
    ) async {
      final controller = controllerFor(InMemoryKeyValueStore(), locale: 'hu');
      addTearDown(controller.dispose);
      await pumpWizardOnPhone(
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
