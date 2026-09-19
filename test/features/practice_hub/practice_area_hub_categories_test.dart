// The Practice Area Hub's "Browse by goal" section: every tile navigates to
// Setup WITH a definition id (the pre-existing goal chips navigated to
// `/practice/setup` bare, which Setup renders as its route-error branch —
// five dead ends), goals are derived from the definitions themselves, and a
// goal with nothing in it is not rendered.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/practice/data/builtin_practice_catalog.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/public.dart'
    show practiceCatalogProvider, practiceHistoryV2ListProvider;
import 'package:strumsight/features/practice_hub/practice_area_hub_categories.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../support/preference_store.dart';

PracticeDefinition _definition({
  required String id,
  required PracticeMode mode,
  List<String> skillTags = const ['test'],
  PracticeDifficulty difficulty = PracticeDifficulty.beginner,
}) => PracticeDefinition(
  id: id,
  schemaVersion: 1,
  titleKey: 'practiceCatalogTestSingleTitle',
  descriptionKey: 'practiceCatalogTestSingleDescription',
  mode: mode,
  source: PracticeSource.builtin,
  meter: const Meter(beatsPerBar: 4),
  defaultTempo: const Tempo(80),
  totalBeats: const BeatPosition(4 * BeatPosition.ticksPerBeat),
  events: const [],
  scoringProfile: _profileFor(mode),
  skillTags: skillTags,
  difficulty: difficulty,
);

ScoringProfile _profileFor(PracticeMode mode) => switch (mode) {
  PracticeMode.strumPattern => ScoringProfile.legacyLearnParity,
  PracticeMode.chordChanges => ScoringProfile.chordChangeDefault,
  PracticeMode.chordProgression => ScoringProfile.chordProgressionDefault,
  PracticeMode.rhythmOnly => ScoringProfile.rhythmOnlyDefault,
  PracticeMode.freePractice => ScoringProfile.freePracticeOpen,
};

AppConfig _config({bool songTrainerV2Enabled = false}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    songTrainerV2Enabled: songTrainerV2Enabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

/// Records every location the hub navigates to; Setup/Learn/Song Trainer
/// render as stubs so the probe measures the URI, not the target screen.
Future<({GoRouter router, List<String> visited})> _pumpHub(
  WidgetTester tester, {
  List<PracticeDefinition>? catalog,
  List<PracticeHistoryEntry> history = const [],
  bool songTrainerV2Enabled = false,
}) async {
  // Tall enough that every catalog tile is fully inside the viewport: a
  // partially visible card's centre lands outside the 800x600 default
  // surface and the tap silently misses (measured in CI).
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final visited = <String>[];
  Widget probe(GoRouterState state) {
    visited.add(state.uri.toString());
    return const SizedBox.shrink();
  }

  final router = GoRouter(
    initialLocation: AppRoutes.practiceHub,
    routes: [
      GoRoute(
        path: AppRoutes.practiceHub,
        builder: (_, _) => const PracticeAreaHubScreen(),
      ),
      GoRoute(path: AppRoutes.practiceSetup, builder: (_, s) => probe(s)),
      GoRoute(path: AppRoutes.practiceCatalog, builder: (_, s) => probe(s)),
      GoRoute(path: AppRoutes.practiceLearn, builder: (_, s) => probe(s)),
      GoRoute(path: AppRoutes.songTrainerLibrary, builder: (_, s) => probe(s)),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        appConfigProvider.overrideWithValue(
          _config(songTrainerV2Enabled: songTrainerV2Enabled),
        ),
        if (catalog != null) practiceCatalogProvider.overrideWithValue(catalog),
        practiceHistoryV2ListProvider.overrideWith((ref) async => history),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (router: router, visited: visited);
}

void main() {
  group('goal derivation is a pure function of the definition', () {
    test('mode decides the goal when no scale/technique tag is present', () {
      expect(
        practiceAreaHubCategoryOf(
          _definition(id: 'a', mode: PracticeMode.rhythmOnly),
        ),
        PracticeAreaHubCategory.warmup,
      );
      expect(
        practiceAreaHubCategoryOf(
          _definition(id: 'b', mode: PracticeMode.freePractice),
        ),
        PracticeAreaHubCategory.warmup,
      );
      expect(
        practiceAreaHubCategoryOf(
          _definition(id: 'c', mode: PracticeMode.chordChanges),
        ),
        PracticeAreaHubCategory.chords,
      );
      expect(
        practiceAreaHubCategoryOf(
          _definition(id: 'd', mode: PracticeMode.chordProgression),
        ),
        PracticeAreaHubCategory.chords,
      );
      expect(
        practiceAreaHubCategoryOf(
          _definition(id: 'e', mode: PracticeMode.strumPattern),
        ),
        PracticeAreaHubCategory.rhythm,
      );
    });

    test('a scale or technique tag wins over the mode', () {
      expect(
        practiceAreaHubCategoryOf(
          _definition(
            id: 'f',
            mode: PracticeMode.strumPattern,
            skillTags: const ['pentatonic'],
          ),
        ),
        PracticeAreaHubCategory.scales,
      );
      expect(
        practiceAreaHubCategoryOf(
          _definition(
            id: 'g',
            mode: PracticeMode.chordChanges,
            skillTags: const ['hammerOn'],
          ),
        ),
        PracticeAreaHubCategory.technique,
      );
    });

    test('groups omit empty goals, keep goal order, sort beginner-first', () {
      final groups = practiceAreaHubGroups([
        _definition(
          id: 'hard',
          mode: PracticeMode.strumPattern,
          difficulty: PracticeDifficulty.advanced,
        ),
        _definition(id: 'easy', mode: PracticeMode.strumPattern),
        _definition(id: 'chords', mode: PracticeMode.chordChanges),
      ]);
      expect(groups.map((g) => g.key), [
        PracticeAreaHubCategory.chords,
        PracticeAreaHubCategory.rhythm,
      ]);
      expect(groups.last.value.map((d) => d.id), ['easy', 'hard']);
    });

    test('the shipped built-in catalog lands entirely in non-empty goals', () {
      final catalog = const BuiltinPracticeCatalog().all();
      final groups = practiceAreaHubGroups(catalog);
      final placed = groups.expand((g) => g.value).length;
      expect(placed, catalog.length);
      expect(groups.every((g) => g.value.isNotEmpty), isTrue);
    });
  });

  group('every goal tile navigates to Setup WITH its definition id', () {
    testWidgets('built-in catalog: one tile per definition, each with ?id=', (
      tester,
    ) async {
      final hub = await _pumpHub(tester);
      final catalog = const BuiltinPracticeCatalog().all();

      for (final definition in catalog) {
        final tile = find.byKey(
          ValueKey('practice-hub-definition-${definition.id}'),
        );
        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(hub.visited.last, contains('id=${definition.id}'));
        expect(hub.visited.last, startsWith(AppRoutes.practiceSetup));

        hub.router.go(AppRoutes.practiceHub);
        await tester.pumpAndSettle();
      }
      // Never a bare `/practice/setup` — that is the dead end this replaces.
      expect(hub.visited, isNot(contains(AppRoutes.practiceSetup)));
      expect(hub.visited.length, catalog.length);
    });

    // The goal CHIPS survived the 2026-09-18 integration as the hub's jump
    // row, and the 2026-09-19 audit integration (R18/B1) re-pointed them at
    // the FILTERED CATALOG instead of one resolved definition — the other
    // nine built-ins had no on-screen entry otherwise. The invariant this
    // cell was written for is unchanged and still asserted directly: a chip
    // never reaches a bare `/practice/setup`, the dead end it replaced.
    testWidgets('no goal chip navigates without a goal', (tester) async {
      final hub = await _pumpHub(tester);
      final chips = find.byType(ActionChip);
      expect(chips, findsWidgets);

      for (var index = 0; index < chips.evaluate().length; index++) {
        final chip = chips.at(index);
        if (tester.widget<ActionChip>(chip).onPressed == null) continue;
        await tester.tap(chip);
        await tester.pumpAndSettle();

        expect(hub.visited.last, startsWith(AppRoutes.practiceCatalog));
        expect(
          Uri.parse(hub.visited.last).queryParameters['category'],
          isNotNull,
        );

        hub.router.go(AppRoutes.practiceHub);
        await tester.pumpAndSettle();
      }
      expect(hub.visited, isNot(contains(AppRoutes.practiceSetup)));
    });

    testWidgets('an empty goal is not rendered; a non-empty one is', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        catalog: [_definition(id: 'only', mode: PracticeMode.chordChanges)],
      );
      expect(
        find.byKey(const ValueKey('practice-hub-group-chords')),
        findsOneWidget,
      );
      for (final category in PracticeAreaHubCategory.values) {
        if (category == PracticeAreaHubCategory.chords) continue;
        expect(
          find.byKey(ValueKey('practice-hub-group-${category.name}')),
          findsNothing,
        );
      }
    });
  });

  group("the recommended card follows the learner's history", () {
    testWidgets('a weak last session recommends the SAME definition again, '
        'named, with the consolidation reason, and the CTA carries its id', (
      tester,
    ) async {
      final l10n = AppLocalizationsEn();
      final hub = await _pumpHub(
        tester,
        history: [_weakSession('builtin.gToDChanges.v1')],
      );

      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('practice-hub-recommended-name')),
            )
            .data,
        l10n.practiceCatalogGToDChangesTitle,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('practice-hub-recommended-reason')),
            )
            .data,
        l10n.practiceNextReasonRepeat,
      );

      await tester.tap(
        find.byKey(const ValueKey('practice-hub-recommended-cta')),
      );
      await tester.pumpAndSettle();
      expect(hub.visited.last, contains('id=builtin.gToDChanges.v1'));
    });

    testWidgets('no history: the easiest entry, as the first session', (
      tester,
    ) async {
      final l10n = AppLocalizationsEn();
      await _pumpHub(tester);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('practice-hub-recommended-reason')),
            )
            .data,
        l10n.practiceNextReasonFirstSession,
      );
    });
  });

  group('the curriculum and the Song Trainer are reachable from the hub', () {
    testWidgets('the course card opens the lesson list route', (tester) async {
      final hub = await _pumpHub(tester);
      await tester.tap(find.byKey(const ValueKey('practice-hub-course-card')));
      await tester.pumpAndSettle();
      expect(hub.visited.last, AppRoutes.practiceLearn);
    });

    testWidgets('the Song Trainer tool follows its rollout flag', (
      tester,
    ) async {
      await _pumpHub(tester);
      expect(
        find.byKey(const ValueKey('practice-hub-song-trainer')),
        findsNothing,
      );

      final hub = await _pumpHub(tester, songTrainerV2Enabled: true);
      final tool = find.byKey(const ValueKey('practice-hub-song-trainer'));
      await tester.tap(tool);
      await tester.pumpAndSettle();
      expect(hub.visited.last, AppRoutes.songTrainerLibrary);
    });
  });
}

PracticeHistoryEntry _weakSession(String definitionId) => PracticeHistoryEntry(
  id: 'weak-$definitionId',
  modeCode: PracticeMode.chordChanges.code,
  sourceCode: PracticeSource.builtin.code,
  createdAt: DateTime.utc(2026, 9, 1, 12),
  definitionId: definitionId,
  displayTitle: '',
  finishReasonCode: 'completedAllTargets',
  activeDuration: const Duration(seconds: 30),
  pausedDuration: Duration.zero,
  attemptsCount: 1,
  finalMetricSnapshot: const PracticeMetricSnapshot(
    completion: PracticeMetricDimensionAvailable(0.3),
    rhythm: PracticeMetricDimensionAvailable(0.3),
    direction: PracticeMetricDimensionAvailable(0.3),
    chord: PracticeMetricDimensionAvailable(0.3),
    overall: PracticeMetricDimensionAvailable(0.3),
  ),
  totalTargets: 10,
  resolvedTargets: 3,
  scorePoints: 0,
  maxCombo: 0,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
  coachingSummary: const [],
  skillTags: const [],
);
