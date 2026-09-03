import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnboardingController', () {
    test('readSeen is false on first run, true once completed', () async {
      final store = InMemoryKeyValueStore();
      expect(OnboardingController.readSeen(store), isFalse);

      final c = ProviderContainer(
        overrides: [
          preferenceStoreOverride(store),
          onboardingSeenProvider.overrideWith(
            () => OnboardingController(false),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(onboardingSeenProvider.notifier).complete();
      expect(c.read(onboardingSeenProvider), isTrue);
      expect(store.values[StorageKeys.onboardingSeen], isTrue); // persisted
      expect(OnboardingController.readSeen(store), isTrue);
    });
  });

  group('OnboardingScreen', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      required VoidCallback onDone,
    }) async {
      final container = ProviderContainer(
        overrides: [
          ...preferenceOverrides(),
          onboardingSeenProvider.overrideWith(
            () => OnboardingController(false),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            // R2 (§0.0): the migrated screen's SsButton now reads the
            // design-system theme extensions — a themeless MaterialApp
            // null-check crashes (L593-class defect).
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: OnboardingScreen(onDone: onDone),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('shows the first page and can advance to the moat page', (
      tester,
    ) async {
      await pump(tester, onDone: () {});
      expect(find.text('See what you play'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Down ↓ and Up ↑'), findsOneWidget);
      // The moat page shows the two direction arrows.
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('Skip completes onboarding and fires onDone', (tester) async {
      var done = false;
      final container = await pump(tester, onDone: () => done = true);
      expect(container.read(onboardingSeenProvider), isFalse);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(done, isTrue);
      expect(container.read(onboardingSeenProvider), isTrue);
    });

    testWidgets('the last page shows the mic call-to-action', (tester) async {
      await pump(tester, onDone: () {});
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Enable mic & start'), findsOneWidget);
    });

    // F4 (E13-R16 javító kör): without an ancestor ProviderScope, the
    // checkpoint read must degrade to the welcome carousel rather than
    // throwing — a deliberate, tested fail-safe (matching
    // `OnboardingController.readSeen`'s own degrade-on-corrupt-value
    // philosophy), not an incidental side effect of a bare smoke test.
    testWidgets(
      'without a ProviderScope, the checkpoint read degrades to the welcome '
      'carousel instead of throwing',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            // R2 (§0.0): the migrated screen's SsButton now reads the
            // design-system theme extensions — a themeless MaterialApp
            // null-check crashes (L593-class defect).
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const OnboardingScreen(),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('See what you play'), findsOneWidget);
      },
    );
  });
}
