// 2026-09-13 — task #7 (4-route sub-round). Four routes measured as
// "registered but never reached by a contextual entry" in the router audit
// (HANDOFF §5.2 (D)):
//
//   - AppRoutes.practiceGeneratorChangeReview
//     (`/practice/generator/change-review`)
//       M12 (HANDOFF §5.2 (D), T1 already shipped `launchChangeReview`):
//       the route is reachable from the upcoming Today-screen revision-review
//       seam. The route's own redirect (`state.extra is PlanRevisionProposal`)
//       keeps a missing extra from rendering the screen. The cells below pin
//       both halves of that contract end-to-end through `launchChangeReview`
//       and through a deep link that arrives without an extra.
//
//   - AppRoutes.songTrainerEditor (`/song-trainer/editor/:songId`)
//       Reachable from the song library's tappable InkWell (read-only
//       sources fall back to overview; editor for everything else).
//
//   - AppRoutes.songTrainerSetup (`/song-trainer/setup/:songId`)
//       Reachable from the song overview's Start button (the only entry
//       the production overview exposes).
//
//   - AppRoutes.songTrainerResult (`/song-trainer/result/:songId`)
//       Reachable from the Song Trainer session route's
//       `NavigateToSongTrainerResult` effect — the only place the mapped
//       result is handed out. The cell below proves the WIRE
//       (`context.push<void>(location, extra: args)`) survives the real
//       router.
//
// `songTrainerV2Enabled: true` is required to register the three song
// trainer routes; `practiceEngineV2Enabled: true` is the related flag for
// the practice generator. Both are on by default outside production; the
// shipped `forShippedBuild` factory turns them on explicitly.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/features/practice_generator/application/usecase/revise_practice_plan.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_change_set.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_revision.dart';
import 'package:strumsight/features/practice_generator/presentation/plan_generation_launch.dart';
import 'package:strumsight/features/practice_generator/presentation/screens/plan_change_review_screen.dart';
import 'package:strumsight/features/practice/public.dart'
    show PracticeAttemptResult, PracticeFinishReason, PracticeSessionResult;
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_overview_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_session_route.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../fixtures/practice_generator/plan/plan_fixtures.dart';
import '../../support/preference_store.dart';

FeatureFlags get _allFeatures => const FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
  adaptiveShellEnabled: false,
  // Three flags gate the four routes the cells below exercise:
  //   - `practiceGeneratorEnabled`     registers the change-review route
  //   - `practiceEngineV2Enabled`      is the related V2 hub flag
  //   - `songTrainerV2Enabled`         registers the three song-trainer
  //                                    routes (library/editor/setup/result)
  // Turning them on for the duration of the test is what gets the four
  // routes registered in the first place.
  practiceEngineV2Enabled: true,
  practiceGeneratorEnabled: true,
  songTrainerV2Enabled: true,
);

Future<({ProviderContainer container, GoRouter router})> _pumpRouter(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      appLoggerProvider.overrideWithValue(const NoopAppLogger()),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: _allFeatures,
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, router: router);
}

/// Bounded wait for a route-level transition (one frame is rarely enough when
/// the push navigates across a shell branch — the shell re-mounts the
/// branch's `Navigator`, and that costs at least one extra paint).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

/// One-day song — the minimal valid SongDocument a screen that calls into
/// the song setup controller can render (OverviewScreen needs at least one
/// section to show the selectable rows).
SongDocument _overviewDocument() {
  final now = DateTime.utc(2026, 9, 13);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('task-seven-song'),
    revision: 0,
    metadata: SongMetadata(title: 'Task-7 song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'task7.song',
      sha256: 'd' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('verse'),
        name: 'Verse',
        startMeasure: 0,
        endMeasureExclusive: 1,
      ),
    ],
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
    tracks: <SongTrack>[
      ChordTrack(
        id: SongTrackId('chords'),
        name: 'Chords',
        instrument: SongInstrument(name: 'Guitar'),
        events: const [],
      ),
    ],
  );
}

/// Bare `SongTrainerResult` — the legacy pre-R8 payload shape, still
/// accepted by `SongTrainerResultArgs.from`. The wire test only needs the
/// route to decode the args; the screen-level retry/next composition has
/// its own test (`song_result_route_test.dart`).
SongTrainerResult _bareResult() => SongTrainerResult(
  sessionResult: const PracticeSessionResult(
    id: 'practice-result-task7',
    activeDuration: Duration(seconds: 4),
    pausedDuration: Duration.zero,
    attempts: <PracticeAttemptResult>[],
    finishReason: PracticeFinishReason.completedAllTargets,
    highestStableTempo: null,
    coachingSummary: <String>[],
  ),
  verdicts: const <SongTrainerVerdict>[],
  measureResults: <SongMeasureTrainerResult>[
    SongMeasureTrainerResult(
      measureIndex: 0,
      verdicts: const <SongTrainerVerdict>[],
      averageEventScore: 0.5,
    ),
  ],
  sectionResults: const <SongSectionTrainerResult>[],
);

/// No-op stand-in for [SongAssetRepository]. The route-reach contract under
/// test in the editor cell only needs the bootstrap layer to be able to
/// resolve the provider — the editor screen reads it on `initState`, but
/// none of the navigation tests exercise an asset write. Returning success
/// (or "not found") keeps the contract honest without dragging in a real
/// fake asset store.
final class _NoopAssetRepository implements SongAssetRepository {
  const _NoopAssetRepository();

  @override
  Future<AppResult<SongAssetStoreReceipt>> put(
    SongAssetWriteRequest request,
  ) async => const AppResult<SongAssetStoreReceipt>.failure(
    UnknownFailure(code: FailureCode.unknown),
  );

  @override
  Future<AppResult<Uint8List?>> get(String sha256) async =>
      const AppResult<Uint8List?>.success(null);

  @override
  Future<AppResult<SongAssetSummary?>> summary(String sha256) async =>
      const AppResult<SongAssetSummary?>.success(null);

  @override
  Future<AppResult<void>> incrementReference(SongAssetHolder holder) async =>
      const AppResult<void>.success(null);

  @override
  Future<AppResult<void>> decrementReference(SongAssetHolder holder) async =>
      const AppResult<void>.success(null);

  @override
  Future<AppResult<void>> permanentlyDelete(String sha256) async =>
      const AppResult<void>.success(null);
}

void main() {
  // ---------------------------------------------------------------------
  // practiceGeneratorChangeReview — the M12 change-review seam.
  //
  // M12 (HANDOFF §5.2 (D), T1): `launchChangeReview` is the single
  // construction site for `PlanRevisionProposal`, the only `extra` shape the
  // route's redirect accepts. A regression that empties the helper, swaps
  // the `extra` type, or drops the route's redirect fails here.
  //
  // The wire test below builds a tiny in-test GoRouter around a single
  // Consumer surface — the same shape `plan_generation_launch_test.dart`
  // uses — so the helper's `context.push` lands on a real router that
  // forwards the navigation to the registered `PlanChangeReviewScreen`.
  // ---------------------------------------------------------------------
  group('AppRoutes.practiceGeneratorChangeReview — `launchChangeReview` (M12, '
      'task #7 #1)', () {
    testWidgets(
      'launchChangeReview pushes /practice/generator/change-review with '
      'the built PlanRevisionProposal as extra and renders the screen',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            ...preferenceOverrides(<String, Object>{}),
            appLoggerProvider.overrideWithValue(const NoopAppLogger()),
            appConfigProvider.overrideWithValue(
              AppConfig(
                environment: AppEnvironment.development,
                apiBaseUrl: AppConfig.devApiBaseUrl,
                flags: _allFeatures,
                diagnosticsToken: AppConfig.devDiagnosticsToken,
                buildMode: 'test',
                appVersion: 'test',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        late final GoRouter router;
        final captured = <Object?>[];
        router = GoRouter(
          initialLocation: '/source',
          routes: <RouteBase>[
            GoRoute(
              path: '/source',
              builder: (_, _) => Consumer(
                builder: (context, ref, _) {
                  return Scaffold(
                    body: ElevatedButton(
                      key: const Key('start-change-review'),
                      onPressed: () {
                        final active = plan();
                        final candidate = plan();
                        unawaited(
                          launchChangeReview(
                            context,
                            ref,
                            activePlan: active,
                            candidateSnapshot: candidate,
                            changes: <PlanChange>[
                              PlanChange(
                                type: PlanChangeType.updated,
                                target: 'day:day.1',
                                before: const <String, Object?>{},
                                after: const <String, Object?>{},
                                reason: PlanChangeReason.learnerReschedule,
                                evidenceRefs: const <String>[
                                  'evidence.tempo-accuracy',
                                ],
                                confidence: 0.9,
                                requiresUserConfirmation: false,
                                reversible: true,
                              ),
                            ],
                            reason: PlanRevisionReason.learnerReschedule,
                            confirmation: PlanChangeConfirmation.pending,
                            // The router-only contract under test is "a real
                            // `PlanRevisionProposal` lands on
                            // `/practice/generator/change-review`" — the
                            // synthetic `previous` that `launchChangeReview`
                            // builds when this is null constructs a
                            // `PlanChangeSet` whose `fromRevisionId` equals
                            // its `toRevisionId`, and the constructor
                            // refuses that with `ArgumentError`. Passing a
                            // real predecessor with a distinct `RevisionId`
                            // routes through the use case's path that
                            // produces a valid `PlanChangeSet`.
                            previous: revision(number: 1),
                          ),
                        );
                      },
                      child: const Text('open'),
                    ),
                  );
                },
              ),
            ),
            GoRoute(
              path: AppRoutes.practiceGeneratorChangeReview,
              builder: (_, state) {
                captured.add(state.extra);
                return PlanChangeReviewScreen(
                  proposal: state.extra! as PlanRevisionProposal,
                  onAccepted: () {},
                  onRejected: () {},
                );
              },
            ),
          ],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
        });

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              theme: SsLightTheme.data(),
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('start-change-review')));
        await _settle(tester);

        expect(router.state.uri.path, AppRoutes.practiceGeneratorChangeReview);
        expect(captured, hasLength(1));
        expect(captured.single, isA<PlanRevisionProposal>());
        expect(
          (captured.single! as PlanRevisionProposal)
              .changeSet
              .changes
              .single
              .type,
          PlanChangeType.updated,
        );
        expect(find.byType(PlanChangeReviewScreen), findsOneWidget);
        // Both callbacks must be wired (not null) — a regression that
        // dropped the handler would surface as a dead button on a screen
        // the user reaches after every revision.
        final screen = tester.widget<PlanChangeReviewScreen>(
          find.byType(PlanChangeReviewScreen),
        );
        expect(screen.onAccepted, isNotNull);
        expect(screen.onRejected, isNotNull);
      },
    );

    testWidgets('a deep link to /practice/generator/change-review without a '
        'PlanRevisionProposal extra bounces to /practice/generator/today '
        '(route redirect stays a hard gate)', (tester) async {
      final harness = await _pumpRouter(
        tester,
        overrides: preferenceOverrides(<String, Object>{}),
      );
      harness.router.go(AppRoutes.practiceGeneratorChangeReview);
      await _settle(tester);
      expect(harness.router.state.uri.path, AppRoutes.practiceGeneratorToday);
      expect(find.byType(PlanChangeReviewScreen), findsNothing);
    });
  });

  // ---------------------------------------------------------------------
  // songTrainerEditor — the library tap-path.
  //
  // The library row InkWell pushes `AppRoutes.songTrainerEditor` when the
  // source is writable, and the overview otherwise. The cell below keeps
  // the document writable (default `createdInApp`) so the editor route is
  // the actual target.
  // ---------------------------------------------------------------------
  group(
    'AppRoutes.songTrainerEditor — the library row\'s tap (task #7 #2)',
    () {
      testWidgets('tapping a writable song row in the library pushes '
          '/song-trainer/editor/<songId> with the songId encoded in the path', (
        tester,
      ) async {
        final repository = InMemorySongRepository();
        final document = _overviewDocument();
        await repository.create(document);
        final harness = await _pumpRouter(
          tester,
          overrides: [
            songRepositoryProvider.overrideWithValue(repository),
            // The editor screen's controller reads the asset repository
            // on `initState` (it never touches it in the route-reach
            // contract under test, but the production provider throws
            // unless the bootstrap layer overrides it). A noop asset
            // repo is enough to prove the WIRE — the route's redirect and
            // path-parameter behaviour — without dragging in a fake
            // asset store the test does not otherwise need.
            songAssetRepositoryProvider.overrideWithValue(
              const _NoopAssetRepository(),
            ),
            ...preferenceOverrides(<String, Object>{}),
          ],
        );
        harness.router.go(AppRoutes.songTrainerLibrary);
        await _settle(tester);
        expect(find.byType(SongLibraryScreen), findsOneWidget);

        await tester.tap(
          find.byKey(ValueKey<String>('song-editor-open-${document.id.value}')),
        );
        await _settle(tester);

        final expected = AppRoutes.songTrainerEditor.replaceFirst(
          ':songId',
          Uri.encodeComponent(document.id.value),
        );
        expect(harness.router.state.uri.path, expected);
        // The path parameter is the literal songId; deep-link consumers
        // can read it back verbatim.
        expect(
          harness.router.state.pathParameters['songId'],
          document.id.value,
        );
      });
    },
  );

  // ---------------------------------------------------------------------
  // songTrainerSetup — the overview Start path.
  //
  // The overview's only entry is the Start button; tapping it pushes
  // `/song-trainer/setup/:songId`. A regression that drops the button's
  // callback (a common dead-control class) or replaces the route name
  // fails here.
  // ---------------------------------------------------------------------
  group(
    'AppRoutes.songTrainerSetup — the overview Start button (task #7 #3)',
    () {
      testWidgets('tapping the Start button on a ready overview pushes '
          '/song-trainer/setup/<songId> with the songId encoded in the path', (
        tester,
      ) async {
        final repository = InMemorySongRepository();
        final document = _overviewDocument();
        await repository.create(document);
        final harness = await _pumpRouter(
          tester,
          overrides: [
            songRepositoryProvider.overrideWithValue(repository),
            ...preferenceOverrides(<String, Object>{}),
          ],
        );
        harness.router.go(
          AppRoutes.songTrainerOverview.replaceFirst(
            ':songId',
            Uri.encodeComponent(document.id.value),
          ),
        );
        await _settle(tester);
        expect(find.byType(SongOverviewScreen), findsOneWidget);
        expect(find.byKey(const Key('song-overview-start')), findsOneWidget);

        // The Start button sits at the bottom of a `ListView` body. In
        // the default 800×600 test viewport it falls just below the
        // hit-test area and `tap()` reports "would not hit test on the
        // specified widget". Resize the surface to a phone-class height
        // so the button lands inside the viewport — this matches what a
        // real device shows, and keeps the route-reach contract under
        // test honest without coupling the test to a specific scroll
        // position.
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('song-overview-start')));
        await _settle(tester);

        final expected = AppRoutes.songTrainerSetup.replaceFirst(
          ':songId',
          Uri.encodeComponent(document.id.value),
        );
        expect(harness.router.state.uri.path, expected);
        expect(
          harness.router.state.pathParameters['songId'],
          document.id.value,
        );
      });
    },
  );

  // ---------------------------------------------------------------------
  // songTrainerResult — the session's NavigateToSongTrainerResult effect.
  //
  // `SongTrainerScreen._onOwnedEffect` is the ONLY place the mapped result
  // is handed out — pushing the route from anywhere else would duplicate
  // the side-effect and break the Retry / Next composition
  // (`song_trainer_screen.dart` line ~175). A regression that empties the
  // effect listener, drops the push, or stops sending the typed args fails
  // here.
  // ---------------------------------------------------------------------
  group('AppRoutes.songTrainerResult — the session\'s '
      'NavigateToSongTrainerResult effect (task #7 #4)', () {
    testWidgets('pushing the result route with the typed SongTrainerResultArgs '
        'lands on /song-trainer/result/<songId> with the args intact (the '
        'context push the owned session effect uses)', (tester) async {
      final harness = await _pumpRouter(
        tester,
        overrides: [
          songRepositoryProvider.overrideWithValue(InMemorySongRepository()),
          ...preferenceOverrides(<String, Object>{}),
        ],
      );
      // Land somewhere first; the effect's caller owns a BuildContext
      // anchored at the session screen, but the WIRE under test is the
      // `context.push<void>(location, extra: args)` — same shape.
      harness.router.go(AppRoutes.songTrainerLibrary);
      await _settle(tester);
      final libraryContext = tester.element(find.byType(SongLibraryScreen));
      final songId = 'task-seven-result';
      final location = AppRoutes.songTrainerResult.replaceFirst(
        ':songId',
        Uri.encodeComponent(songId),
      );
      // A bare result (the pre-R8 shape) is enough to prove the route
      // accepts the args factory's accepted types — the route's
      // `SongTrainerResultArgs.from` reads it back to a typed pair.
      final args = SongTrainerResultArgs(result: _bareResult());
      GoRouter.of(libraryContext).push<void>(location, extra: args);
      await _settle(tester);

      expect(harness.router.state.uri.path, location);
      expect(harness.router.state.pathParameters['songId'], songId);
      // The route's `SongTrainerResultArgs.from(state.extra)` survived
      // the push (it would have thrown on the build if it had not).
      expect(tester.takeException(), isNull);
    });
  });
}
