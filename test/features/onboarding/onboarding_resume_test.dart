import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/features/onboarding/screens/permission_primer_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

/// E13-R16 (ADR 0281 §5, A6/A7) — the onboarding checkpoint. A6: an
/// interrupted onboarding resumes where it left off. A7: the legacy
/// single-bool state migrates (an already-onboarded user is never replayed).
void main() {
  group('A7 — legacy state migration', () {
    test('an empty store (genuine first run) starts at welcome', () {
      final store = InMemoryKeyValueStore();
      expect(OnboardingStepController.readStep(store), OnboardingStep.welcome);
    });

    test('a legacy seen=true store (pre-checkpoint build) inherits done — not '
        'replayed through the flow', () {
      final store = InMemoryKeyValueStore({StorageKeys.onboardingSeen: true});
      expect(OnboardingStepController.readStep(store), OnboardingStep.done);
    });

    test('a legacy seen=false store starts at welcome', () {
      final store = InMemoryKeyValueStore({StorageKeys.onboardingSeen: false});
      expect(OnboardingStepController.readStep(store), OnboardingStep.welcome);
    });

    test(
      'an explicit checkpoint wins over the legacy bool, in either direction',
      () {
        final aheadOfSeen = InMemoryKeyValueStore({
          StorageKeys.onboardingSeen: false,
          OnboardingStepController.storageKey: OnboardingStep.permission.index,
        });
        expect(
          OnboardingStepController.readStep(aheadOfSeen),
          OnboardingStep.permission,
        );

        final explicitWelcomeDespiteSeen = InMemoryKeyValueStore({
          StorageKeys.onboardingSeen: true,
          OnboardingStepController.storageKey: OnboardingStep.welcome.index,
        });
        expect(
          OnboardingStepController.readStep(explicitWelcomeDespiteSeen),
          OnboardingStep.welcome,
        );
      },
    );

    test(
      'a corrupt/out-of-range stored step degrades to the bool-derived default',
      () {
        final store = InMemoryKeyValueStore({
          StorageKeys.onboardingSeen: true,
          OnboardingStepController.storageKey: 99,
        });
        expect(OnboardingStepController.readStep(store), OnboardingStep.done);
      },
    );
  });

  group('A6 — the checkpoint persists forward progress', () {
    test('advanceTo updates state immediately and persists it', () async {
      final store = InMemoryKeyValueStore();
      final container = ProviderContainer(
        overrides: [preferenceStoreOverride(store)],
      );
      addTearDown(container.dispose);

      expect(container.read(onboardingStepProvider), OnboardingStep.welcome);
      await container
          .read(onboardingStepProvider.notifier)
          .advanceTo(OnboardingStep.permission);

      expect(container.read(onboardingStepProvider), OnboardingStep.permission);
      expect(
        OnboardingStepController.readStep(store),
        OnboardingStep.permission,
      );
    });
  });

  group('A6 — OnboardingScreen resumes at the checkpointed step', () {
    Future<void> pumpAt(WidgetTester tester, OnboardingStep step) async {
      final store = InMemoryKeyValueStore({
        OnboardingStepController.storageKey: step.index,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [preferenceStoreOverride(store)],
          child: MaterialApp(
            // R2 (§0.0, extended measurement): the migrated OnboardingScreen
            // now reads the design-system theme extensions via SsButton — a
            // themeless MaterialApp null-check crashes (L593-class defect).
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a checkpoint left at the permission step shows the primer directly, '
      'not the intro carousel from page 0',
      (tester) async {
        await pumpAt(tester, OnboardingStep.permission);

        expect(find.byType(PermissionPrimerScreen), findsOneWidget);
        expect(find.text('See what you play'), findsNothing);
      },
    );

    testWidgets('a fresh (welcome) checkpoint shows the intro carousel', (
      tester,
    ) async {
      await pumpAt(tester, OnboardingStep.welcome);

      expect(find.text('See what you play'), findsOneWidget);
    });
  });

  group('F3 — the persisted step order is pinned (on-disk contract)', () {
    test('OnboardingStep names AND indices are pinned literally — the order IS '
        'the on-disk format (advanceTo persists step.index); reordering or '
        'inserting a value silently shifts every stored checkpoint', () {
      expect(OnboardingStep.values.map((e) => e.name).toList(), [
        'welcome',
        'permission',
        'done',
      ]);
      expect(OnboardingStep.welcome.index, 0);
      expect(OnboardingStep.permission.index, 1);
      expect(OnboardingStep.done.index, 2);
    });
  });
}
