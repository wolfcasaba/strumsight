// E18-R01 emulator finding F6 — "Browse by goal → Chords" landed on
// "Practice unavailable": the chips navigated to the bare `/practice/setup`
// with no definition id. Now a chip carries the id the catalogue resolves
// for its goal, and a goal the catalogue cannot serve says so in place
// (a SnackBar) instead of navigating to a dead end.
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

const _freePlayOnly = PracticeDefinition(
  id: 'test.free.v1',
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
  skillTags: ['freePlay'],
);

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

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets(
    'the Chords chip opens Setup WITH the resolved chord-changes definition',
    (tester) async {
      final router = await _pumpHub(tester);

      await tester.tap(find.byKey(const ValueKey('practice-hub-goal-chords')));
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '/practice/setup?id=builtin.gToDChanges.v1',
      );
    },
  );

  testWidgets('Warm-up and Rhythm resolve too; each to a different practice', (
    tester,
  ) async {
    final router = await _pumpHub(tester);

    await tester.tap(find.byKey(const ValueKey('practice-hub-goal-warmup')));
    await tester.pumpAndSettle();
    final warmup = router.state.uri.toString();
    expect(warmup, '/practice/setup?id=builtin.quarterDownstrokes.v1');

    router.go(AppRoutes.practiceHub);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('practice-hub-goal-rhythm')));
    await tester.pumpAndSettle();
    expect(
      router.state.uri.toString(),
      '/practice/setup?id=builtin.rhythmOnlyQuarters.v1',
    );
  });

  testWidgets(
    'a goal the built-in catalogue cannot serve (Scales) says so in place — '
    'no navigation, never "Practice unavailable"',
    (tester) async {
      final router = await _pumpHub(tester);
      expect(find.byType(ActionChip), findsNWidgets(5));

      await tester.tap(find.byKey(const ValueKey('practice-hub-goal-scales')));
      await tester.pump();

      expect(find.text(l10n.practiceAreaHubGoalUnavailable), findsOneWidget);
      expect(router.state.uri.path, AppRoutes.practiceHub);
      expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
    },
  );

  testWidgets('a catalogue with nothing goal-shaped: every chip explains, none '
      'navigates', (tester) async {
    final router = await _pumpHub(
      tester,
      overrides: [
        practiceCatalogProvider.overrideWithValue(const [_freePlayOnly]),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('practice-hub-goal-chords')));
    await tester.pump();
    expect(find.text(l10n.practiceAreaHubGoalUnavailable), findsOneWidget);
    expect(router.state.uri.path, AppRoutes.practiceHub);
  });
}
