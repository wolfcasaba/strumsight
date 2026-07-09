import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/onboarding/onboarding_provider.dart';
import 'package:music_theory/features/onboarding/screens/onboarding_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OnboardingController', () {
    test('load() is false on first run, true once completed', () async {
      expect(await OnboardingController.load(), isFalse);

      final c = ProviderContainer(overrides: [
        onboardingSeenProvider.overrideWith(() => OnboardingController(false)),
      ]);
      addTearDown(c.dispose);
      await c.read(onboardingSeenProvider.notifier).complete();
      expect(c.read(onboardingSeenProvider), isTrue);
      expect(await OnboardingController.load(), isTrue); // persisted
    });
  });

  group('OnboardingScreen', () {
    Future<ProviderContainer> pump(WidgetTester tester,
        {required VoidCallback onDone}) async {
      final container = ProviderContainer(overrides: [
        onboardingSeenProvider.overrideWith(() => OnboardingController(false)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingScreen(onDone: onDone),
        ),
      ));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('shows the first page and can advance to the moat page',
        (tester) async {
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
  });
}
