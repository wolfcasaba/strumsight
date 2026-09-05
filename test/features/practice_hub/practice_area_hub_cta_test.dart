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

/// A minimal, self-contained definition — mirrors the shape
/// `practice_catalog_controller_test.dart` uses for its own override cell,
/// but with a distinct id so a bedrótozott `'builtin.quarterDownstrokes.v1'`
/// literal in the CTA would fail this file's (b) cell (brief §6.1).
const _overrideDefinition = PracticeDefinition(
  id: 'test.first.v1',
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
  skillTags: ['test'],
);

const _ctaKey = ValueKey('practice-hub-recommended-cta');

Future<GoRouter> _pumpHub(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// ADR 0508 D3/D4 — the recommended-practice CTA's URI matrix (brief §6 A4):
/// (a) the shipped built-in catalog, (b) an overridden catalog whose first
/// entry is NOT the built-in id (kills a bedrótozott literal), and (c) an
/// empty catalog (no CTA at all, not a fallback navigation).
void main() {
  group('A4 — the CTA URI-mátrix', () {
    testWidgets(
      "(a) the built-in catalog: the CTA carries the catalog's first id",
      (tester) async {
        final router = await _pumpHub(tester);

        await tester.tap(find.byKey(_ctaKey));
        await tester.pumpAndSettle();

        expect(
          router.state.uri.toString(),
          '/practice/setup?id=builtin.quarterDownstrokes.v1',
        );
      },
    );

    testWidgets(
      '(b) an overridden catalog: the CTA carries the OVERRIDDEN first id, '
      'not a hardcoded literal',
      (tester) async {
        final router = await _pumpHub(
          tester,
          overrides: [
            practiceCatalogProvider.overrideWithValue(const [
              _overrideDefinition,
            ]),
          ],
        );

        await tester.tap(find.byKey(_ctaKey));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/practice/setup?id=test.first.v1');
      },
    );

    testWidgets('(c) an empty catalog: no recommended card at all', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pumpHub(
        tester,
        overrides: [practiceCatalogProvider.overrideWithValue(const [])],
      );

      expect(find.byKey(_ctaKey), findsNothing);
      expect(find.text(l10n.practiceAreaHubRecommendedTitle), findsNothing);
      expect(find.text(l10n.practiceAreaHubRecommendedMessage), findsNothing);
    });
  });
}
