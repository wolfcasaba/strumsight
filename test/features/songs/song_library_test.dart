// E13-R23 — Song Library acceptance A2 (source/license visible), A3
// (read-only songs cannot be edited), A7 (legacy songs/setlists routes still
// work) and A8 (search/filter state survives a push-and-return round trip).
//
// §0.0/B/R16 (measured): SongSummary has no `license` field and no
// `community` source — the producers are `SongSummary.sourceType`,
// `SongMetadata.copyright` (Overview only — the summary index never carries
// it) and `SongSummary.capability.canPersist`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/adaptive_shell_routes.dart'
    show legacyRedirects;
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

void main() {
  // ─── A7: legacy routes are an unmodified regression guard ──────────────
  test(
    'legacy /setlists still redirects to the adaptive-shell songs/setlists destination',
    () {
      expect(legacyRedirects[AppRoutes.setlists], AppRoutes.songsSetlists);
      expect(legacyRedirects.containsKey(AppRoutes.songs), isFalse);
    },
  );

  // ─── A2: source is visible in the list ──────────────────────────────────
  testWidgets('the source badge is visible on each library row', (
    tester,
  ) async {
    final repository = _SummaryRepository(<SongSummary>[
      _summary(
        id: 'json-song',
        title: 'Native Song',
        sourceType: SongSourceType.strumSightJson,
        capability: null,
      ),
    ]);
    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(
      find.byKey(const Key('song-source-badge-json-song')),
      findsOneWidget,
    );
    expect(find.text('StrumSight JSON'), findsOneWidget);
  });

  // ─── A3: a read-only source cannot be launched into the editor ─────────
  testWidgets(
    'tapping a read-only (canPersist=false) row opens view mode, not the editor',
    (tester) async {
      final repository = _SummaryRepository(<SongSummary>[
        _summary(
          id: 'readonly-song',
          title: 'Read Only Song',
          sourceType: SongSourceType.legacyLocal,
          capability: SongCapabilitySummary(
            canPersist: false,
            canTrain: true,
            canExport: true,
            chordScoring: true,
            pitchScoring: false,
            lastValidatedAt: _fixedInstant,
          ),
        ),
      ]);

      final router = GoRouter(
        initialLocation: AppRoutes.songTrainerLibrary,
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.songTrainerLibrary,
            builder: (_, _) => const SongLibraryScreen(),
          ),
          GoRoute(
            path: AppRoutes.songTrainerEditor,
            builder: (_, state) => Scaffold(
              body: Text('editor:${state.pathParameters['songId']}'),
            ),
          ),
          GoRoute(
            path: AppRoutes.songTrainerOverview,
            builder: (_, state) => Scaffold(
              body: Text('overview:${state.pathParameters['songId']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            songRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();

      // Read-only lock badge is present.
      expect(
        find.byKey(const Key('song-summary-readonly-readonly-song')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('song-editor-open-readonly-song')));
      await tester.pumpAndSettle();

      // Editor was NOT reached — the read-only row opens view mode instead.
      expect(find.text('editor:readonly-song'), findsNothing);
      expect(find.text('overview:readonly-song'), findsOneWidget);
    },
  );

  testWidgets('an editable (canPersist=true) row still opens the editor', (
    tester,
  ) async {
    final repository = _SummaryRepository(<SongSummary>[
      _summary(
        id: 'editable-song',
        title: 'Editable Song',
        sourceType: SongSourceType.createdInApp,
        capability: SongCapabilitySummary(
          canPersist: true,
          canTrain: true,
          canExport: true,
          chordScoring: true,
          pitchScoring: false,
          lastValidatedAt: _fixedInstant,
        ),
      ),
    ]);

    final router = GoRouter(
      initialLocation: AppRoutes.songTrainerLibrary,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.songTrainerLibrary,
          builder: (_, _) => const SongLibraryScreen(),
        ),
        GoRoute(
          path: AppRoutes.songTrainerEditor,
          builder: (_, state) =>
              Scaffold(body: Text('editor:${state.pathParameters['songId']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          songRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('song-summary-readonly-editable-song')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('song-editor-open-editable-song')));
    await tester.pumpAndSettle();

    expect(find.text('editor:editable-song'), findsOneWidget);
  });

  // ─── A8: search/filter state survives a push-and-return round trip ─────
  testWidgets(
    'search text and source filter persist after pushing and returning from another route',
    (tester) async {
      final repository = _SummaryRepository(<SongSummary>[
        _summary(
          id: 'json',
          title: 'Zulu JSON',
          sourceType: SongSourceType.strumSightJson,
          capability: null,
        ),
        _summary(
          id: 'midi',
          title: 'Alpha MIDI',
          sourceType: SongSourceType.midi,
          capability: null,
        ),
      ]);

      final router = GoRouter(
        initialLocation: AppRoutes.songTrainerLibrary,
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.songTrainerLibrary,
            builder: (_, _) => const SongLibraryScreen(),
          ),
          GoRoute(
            path: AppRoutes.songTrainerNewEditor,
            builder: (_, _) => const Scaffold(body: Text('new editor')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            songRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Alpha');
      await tester.pump();
      expect(find.text('Alpha MIDI'), findsOneWidget);
      expect(find.text('Zulu JSON'), findsNothing);

      // Push a new route on top (the create-song entry point), then return.
      await tester.tap(find.byKey(const Key('song-editor-create')));
      await tester.pumpAndSettle();
      expect(find.text('new editor'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      // The Library screen was never disposed while covered — the filter
      // state (owned by the autoDispose provider a live widget still
      // watches) survived the round trip.
      expect(find.text('Alpha'), findsOneWidget); // still in the TextField
      expect(find.text('Alpha MIDI'), findsOneWidget);
      expect(find.text('Zulu JSON'), findsNothing);
    },
  );

  // ─── A8 (strong): the filter survives a REAL dispose, not just a cover ──
  testWidgets(
    'search text and filtered results survive a real dispose and re-entry '
    'of the Library screen',
    (tester) async {
      final repository = _SummaryRepository(<SongSummary>[
        _summary(
          id: 'json',
          title: 'Zulu JSON',
          sourceType: SongSourceType.strumSightJson,
          capability: null,
        ),
        _summary(
          id: 'midi',
          title: 'Alpha MIDI',
          sourceType: SongSourceType.midi,
          capability: null,
        ),
      ]);

      // Same ProviderScope instance across both pumps (no key change on it),
      // so only the `home` subtree remounts — the Library screen is really
      // disposed and re-created, not merely covered by a pushed route.
      Widget buildApp({required bool showLibrary}) => ProviderScope(
        overrides: <Override>[
          songRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: showLibrary
              ? const SongLibraryScreen()
              : const Scaffold(body: Text('elsewhere')),
        ),
      );

      await tester.pumpWidget(buildApp(showLibrary: true));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Alpha');
      await tester.pump();
      expect(find.text('Alpha MIDI'), findsOneWidget);
      expect(find.text('Zulu JSON'), findsNothing);

      // Swap the Library out of `home` entirely — the widget type at that
      // slot changes, so the element (and its autoDispose controller) is
      // really unmounted, not just covered.
      await tester.pumpWidget(buildApp(showLibrary: false));
      await tester.pump();
      expect(find.text('elsewhere'), findsOneWidget);
      expect(find.byType(SongLibraryScreen), findsNothing);

      // Real re-entry: a brand-new SongLibraryScreen element/state.
      await tester.pumpWidget(buildApp(showLibrary: true));
      await tester.pump();

      expect(find.text('Alpha'), findsOneWidget); // TextField shows it again
      expect(find.text('Alpha MIDI'), findsOneWidget);
      expect(find.text('Zulu JSON'), findsNothing);
    },
  );
}

final DateTime _fixedInstant = DateTime.utc(2026, 8, 1);

Widget _app(SongRepository repository) => ProviderScope(
  overrides: <Override>[songRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    theme: SsLightTheme.data(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const SongLibraryScreen(),
  ),
);

SongSummary _summary({
  required String id,
  required String title,
  required SongSourceType sourceType,
  required SongCapabilitySummary? capability,
}) => SongSummary(
  documentId: SongId(id),
  title: title,
  artist: null,
  tags: const <String>[],
  updatedAt: DateTime.utc(2026, 8, 5),
  lastPracticedAt: DateTime.utc(2026, 8, 5),
  capability: capability,
  sourceType: sourceType,
  favorite: false,
  archived: false,
  revision: 0,
  documentHash: '0' * 64,
  trashed: false,
);

final class _SummaryRepository implements SongRepository {
  const _SummaryRepository(this._summaries);

  final List<SongSummary> _summaries;

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) async =>
      AppResult<List<SongSummary>>.success(_summaries);

  @override
  Future<AppResult<void>> create(SongDocument document) =>
      throw UnimplementedError();

  @override
  Future<AppResult<SongDocument?>> get(SongId id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> moveToTrash(SongId id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> restore(SongId id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) => throw UnimplementedError();
}
