// A2a (2) — the Practice Area Hub's five category chips.
//
// Before the fix every chip called `context.go(AppRoutes.practiceSetup)` with
// NO `?id=` query, and `practice_setup_screen.dart` reads that query: a
// missing id resolves to `PracticeSetupRequest.missing`, so every chip landed
// on the setup screen's error panel. A chip must either carry an id the
// catalog actually knows (the same shape the recommended CTA already builds)
// or be disabled when its category has no content at all.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/public.dart'
    show practiceCatalogProvider;
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// A definition tagged into the `chords` category but with an id that shares
/// nothing with the built-in catalog — a hardcoded literal in the chip would
/// fail the override cell below.
const _overrideChordDefinition = PracticeDefinition(
  id: 'test.only.chords.v1',
  schemaVersion: 1,
  titleKey: 'practiceCatalogTestSingleTitle',
  descriptionKey: 'practiceCatalogTestSingleDescription',
  mode: PracticeMode.freePractice,
  source: PracticeSource.builtin,
  meter: Meter(beatsPerBar: 4),
  defaultTempo: Tempo(80),
  totalBeats: BeatPosition(4 * BeatPosition.ticksPerBeat),
  events: [],
  scoringProfile: ScoringProfile.freePracticeOpen,
  skillTags: ['chordChanges'],
);

Future<GoRouter> _pumpHub(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Locale? locale,
}) async {
  // The hub is a lazily built ListView and the goal chips sit below the
  // quick tools and the plan-builder row, so on the 800x600 default surface
  // the chip subtree is never BUILT and every finder resolves to nothing.
  // Same remedy the hub's other widget cells use: a tall surface, measured
  // properties unchanged.
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: AppRoutes.practiceHub,
    routes: [
      GoRoute(
        path: AppRoutes.practiceHub,
        builder: (_, _) => const PracticeAreaHubScreen(),
      ),
      GoRoute(
        path: AppRoutes.practiceSetup,
        builder: (_, _) => const SizedBox.shrink(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.dark(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder _chip(String label) => find.widgetWithText(ActionChip, label);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final categoryLabels = <String>[
    l10n.practiceAreaHubCategoryWarmup,
    l10n.practiceAreaHubCategoryChords,
    l10n.practiceAreaHubCategoryRhythm,
    l10n.practiceAreaHubCategoryScales,
    l10n.practiceAreaHubCategoryTechnique,
  ];

  // The per-category DESTINATION table. "An id the catalog knows" is not the
  // contract — the brief asks for a valid definition id FOR THAT CATEGORY, so
  // every chip is pinned to the exercise its own label promises. Without this
  // table a mapping that collapses two categories onto one exercise (Warm-up
  // and Rhythm both resolving to the first quarter-note drill, because both
  // claim the generic `quarterNotes` tag) passes unnoticed.
  final expectedDefinitionId = <String, String>{
    l10n.practiceAreaHubCategoryWarmup: 'builtin.quarterDownstrokes.v1',
    l10n.practiceAreaHubCategoryChords: 'builtin.gToDChanges.v1',
    l10n.practiceAreaHubCategoryRhythm: 'builtin.alternatingEighths.v1',
    // Technique resolves to the DEDICATED off-beat drill, not to the folk
    // strumming pattern that merely happens to carry `syncopation` as a
    // secondary tag and is declared earlier in the catalog.
    l10n.practiceAreaHubCategoryTechnique: 'builtin.syncopatedUps.v1',
  };

  group('A2a — the category chip URI matrix', () {
    for (final label in categoryLabels) {
      testWidgets('"$label" either navigates with a known id or is disabled', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final knownIds = container
            .read(practiceCatalogProvider)
            .map((definition) => definition.id)
            .toSet();

        final router = await _pumpHub(tester);
        await tester.ensureVisible(_chip(label));
        await tester.pumpAndSettle();

        final chip = tester.widget<ActionChip>(_chip(label));
        if (chip.onPressed == null) {
          // A category with no content is DISABLED, never a chip that
          // navigates into the setup screen's error panel.
          expect(
            label,
            l10n.practiceAreaHubCategoryScales,
            reason: 'only Scales has no built-in content today',
          );
          return;
        }

        await tester.tap(_chip(label));
        await tester.pumpAndSettle();

        final uri = router.state.uri;
        expect(uri.path, AppRoutes.practiceSetup, reason: label);
        expect(
          knownIds,
          contains(uri.queryParameters['id']),
          reason: '"$label" must carry an id the catalog can resolve',
        );
        expect(
          uri.queryParameters['id'],
          expectedDefinitionId[label],
          reason:
              '"$label" must open an exercise OF ITS OWN category, '
              'not merely one the catalog happens to contain',
        );
      });
    }

    testWidgets('no two categories open the same exercise', (tester) async {
      final router = await _pumpHub(tester);
      final openedBy = <String, String>{};

      for (final label in expectedDefinitionId.keys) {
        await tester.ensureVisible(_chip(label));
        await tester.pumpAndSettle();
        await tester.tap(_chip(label));
        await tester.pumpAndSettle();

        final id = router.state.uri.queryParameters['id'];
        expect(id, isNotNull, reason: label);
        expect(
          openedBy,
          isNot(contains(id)),
          reason: '"$label" opens the same exercise as "${openedBy[id]}"',
        );
        openedBy[id!] = label;

        router.go(AppRoutes.practiceHub);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Scales has no built-in content, so its chip is disabled', (
      tester,
    ) async {
      await _pumpHub(tester);
      await tester.ensureVisible(_chip(l10n.practiceAreaHubCategoryScales));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ActionChip>(_chip(l10n.practiceAreaHubCategoryScales))
            .onPressed,
        isNull,
      );
    });

    // A disabled chip with no feedback is indistinguishable from a broken
    // one. Both locales are asserted because the strings are NEW ARB keys:
    // an English-only addition would ship the fallback to Hungarian users,
    // and a missing `@`-metadata/key pair would not even compile here.
    for (final locale in const [Locale('en'), Locale('hu')]) {
      testWidgets('the disabled Scales chip announces its reason '
          '(${locale.languageCode})', (tester) async {
        // Disposed INLINE, not via addTearDown: the framework verifies
        // that no SemanticsHandle is alive before tearDown callbacks run.
        final semantics = tester.ensureSemantics();
        final localised = lookupAppLocalizations(locale);

        await _pumpHub(tester, locale: locale);
        final scales = _chip(localised.practiceAreaHubCategoryScales);
        await tester.ensureVisible(scales);
        await tester.pumpAndSettle();

        expect(tester.widget<ActionChip>(scales).onPressed, isNull);

        // Sighted feedback: the long-press/hover tooltip.
        final tooltip = tester.widget<Tooltip>(
          find.ancestor(of: scales, matching: find.byType(Tooltip)),
        );
        expect(
          tooltip.message,
          localised.practiceAreaHubCategoryComingSoonTooltip,
        );

        // Screen-reader feedback: the reason rides on the chip's own node,
        // so the label and the hint are announced together.
        final data = tester.getSemantics(scales).getSemanticsData();
        expect(data.label, contains(localised.practiceAreaHubCategoryScales));
        expect(
          data.hint,
          contains(localised.practiceAreaHubCategoryComingSoonHint),
        );

        semantics.dispose();
      });
    }

    testWidgets('the id comes from the CATALOG, not a hardcoded literal', (
      tester,
    ) async {
      final router = await _pumpHub(
        tester,
        overrides: [
          practiceCatalogProvider.overrideWithValue(const [
            _overrideChordDefinition,
          ]),
        ],
      );
      await tester.ensureVisible(_chip(l10n.practiceAreaHubCategoryChords));
      await tester.pumpAndSettle();

      await tester.tap(_chip(l10n.practiceAreaHubCategoryChords));
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '/practice/setup?id=test.only.chords.v1',
      );
    });

    testWidgets('an empty catalog disables every category chip', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        overrides: [practiceCatalogProvider.overrideWithValue(const [])],
      );

      for (final label in categoryLabels) {
        await tester.ensureVisible(_chip(label));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ActionChip>(_chip(label)).onPressed,
          isNull,
          reason: '"$label" must not navigate without a definition id',
        );
      }
    });
  });
}
