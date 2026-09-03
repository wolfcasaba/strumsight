import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/components/actions/ss_button.dart';
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

    // A3 (§6/§0.0/R5) — the migrated screen must not overflow at the
    // required 1.5/2.0 textScale threshold pair, in both `en` and `hu`.
    group('A3 — textScale variant matrix (1.5 / 2.0 × en / hu)', () {
      Future<ProviderContainer> pumpVariant(
        WidgetTester tester, {
        required double textScale,
        required Locale locale,
      }) async {
        // MAJOR-1 (§0.0/R5, E15-R11 review MAJOR-2): the default
        // flutter_test surface (800x600) is wider than any phone — run the
        // matrix at phone width so it can actually see an overflow.
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

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
              theme: SsLightTheme.data(),
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: const OnboardingScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return container;
      }

      for (final textScale in [1.5, 2.0]) {
        for (final locale in [const Locale('en'), const Locale('hu')]) {
          testWidgets('renders without overflow at $textScale ($locale)', (
            tester,
          ) async {
            await pumpVariant(tester, textScale: textScale, locale: locale);

            expect(tester.takeException(), isNull);
          });
        }
      }

      testWidgets('the welcome carousel uses the design-system SsButton', (
        tester,
      ) async {
        await pumpVariant(tester, textScale: 1.0, locale: const Locale('en'));

        expect(find.byType(SsButton), findsWidgets);
      });
    });

    // BLOCKER-2 (E15-R11 review MAJOR-1): the main CTA must render its full
    // label at the required 2.0x text scale, on both locales, on phone
    // width — not just avoid an overflow EXCEPTION (which the ellipsis on
    // SsButton would have suppressed).
    group(
      'CTA label never truncates at 2.0x text scale (E15-R11 review MAJOR-1)',
      () {
        Future<void> pumpToLastPage(
          WidgetTester tester, {
          required Locale locale,
          required double textScale,
        }) async {
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

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
                theme: SsLightTheme.data(),
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: const OnboardingScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final l10n = lookupAppLocalizations(locale);
          await tester.tap(find.text(l10n.onboardNext));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.onboardNext));
          await tester.pumpAndSettle();
        }

        for (final locale in [const Locale('en'), const Locale('hu')]) {
          testWidgets(
            '$locale CTA renders in full at 2.0x text scale, no ellipsis',
            (tester) async {
              await pumpToLastPage(tester, locale: locale, textScale: 2.0);

              final l10n = lookupAppLocalizations(locale);
              final ctaText = find.text(l10n.onboardFirstWin);
              expect(ctaText, findsOneWidget);
              expect(
                find.ancestor(of: ctaText, matching: find.byType(FilledButton)),
                findsOneWidget,
                reason:
                    'the CTA must stay a plain FilledButton, not the '
                    'ellipsis-prone SsButton',
              );

              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: ctaText, matching: find.byType(RichText)),
              );
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: 'the CTA label must render in full, not ellipsize',
              );
              expect(tester.takeException(), isNull);
            },
          );
        }
      },
    );
  });
}
