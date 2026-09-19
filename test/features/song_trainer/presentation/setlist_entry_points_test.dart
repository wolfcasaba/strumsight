// WP-H1 — a Setlist V2 lista és a dalcsomag-munkamenet BELÉPÉSI PONTJAI.
//
// A körig mindkét képernyőre igaz volt, hogy semmi nem hivatkozta őket a
// `lib/`-ben (mérve: `dart run tool/check_screen_reachability.dart`). Ezek a
// cellák a felületről induló utat mérik: a dalok képernyő dalcsomag-gombja a
// V2 listára visz (Song Trainer V2 mellett), a lista sora pedig a
// mód-választáson át a dalcsomag-munkamenet ÚTVONALÁRA.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/setlist_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_session_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/setlists/setlist_session_entry.dart';
import 'package:strumsight/features/songs/screens/setlist_list_screen.dart';
import 'package:strumsight/features/songs/screens/song_list_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the songs screen opens the Setlist V2 list when Song Trainer '
      'V2 is on', (tester) async {
    final router = _router();
    await tester.pumpWidget(_app(router, songTrainerEnabled: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('songs-open-setlists')));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.songTrainerSetlists);
    expect(find.byType(SetlistListScreenV2), findsOneWidget);
    expect(find.byType(SetlistListScreen), findsNothing);
  });

  testWidgets('with the flag off the same action keeps opening the legacy '
      'setlist list (A5)', (tester) async {
    final router = _router();
    await tester.pumpWidget(_app(router, songTrainerEnabled: false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('songs-open-setlists')));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.songs);
    expect(find.byType(SetlistListScreen), findsOneWidget);
    expect(find.byType(SetlistListScreenV2), findsNothing);
  });

  testWidgets('opening a setlist asks for the mode and starts the setlist '
      'session route', (tester) async {
    final router = _router();
    await tester.pumpWidget(_app(router, songTrainerEnabled: true));
    router.go(AppRoutes.songTrainerSetlists);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('setlist-open-setlist-1')));
    await tester.pumpAndSettle();

    // The list asks instead of choosing a mode for the user: Practice is
    // scored (microphone), Performance is playback-only.
    expect(find.byKey(const Key('setlist-run-practice')), findsOneWidget);
    expect(find.byKey(const Key('setlist-run-performance')), findsOneWidget);

    await tester.tap(find.byKey(const Key('setlist-run-practice')));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.songTrainerSetlistSession);
    final screen = tester.widget<SetlistSessionScreen>(
      find.byType(SetlistSessionScreen),
    );
    expect(screen.mode, SetlistSessionMode.practice);
    expect(screen.setlist.id, 'setlist-1');
    expect(
      screen.createPracticeRunner,
      isNotNull,
      reason: 'the practice runner factory is the production session runner',
    );
  });

  testWidgets('the performance choice starts the same route in playback-only '
      'mode', (tester) async {
    final router = _router();
    await tester.pumpWidget(_app(router, songTrainerEnabled: true));
    router.go(AppRoutes.songTrainerSetlists);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('setlist-open-setlist-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setlist-run-performance')));
    await tester.pumpAndSettle();

    final screen = tester.widget<SetlistSessionScreen>(
      find.byType(SetlistSessionScreen),
    );
    expect(screen.mode, SetlistSessionMode.performance);
  });

  testWidgets('the setlist session route without its args falls back to the '
      'list instead of crashing on a missing extra', (tester) async {
    final router = _router();
    await tester.pumpWidget(_app(router, songTrainerEnabled: true));
    router.go(AppRoutes.songTrainerSetlistSession);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.songTrainerSetlists);
    expect(find.byType(SetlistListScreenV2), findsOneWidget);
  });
}

/// A production route table for the three screens under test, built with the
/// same factories `app_router.dart` uses.
GoRouter _router() => GoRouter(
  initialLocation: AppRoutes.songs,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.songs,
      builder: (_, _) => const SongListScreen(),
    ),
    GoRoute(
      path: AppRoutes.songTrainerSetlists,
      builder: (_, _) =>
          Consumer(builder: (_, ref, _) => buildSetlistListScreenV2(ref)),
    ),
    GoRoute(
      path: AppRoutes.songTrainerSetlistSession,
      redirect: (_, state) => state.extra is SetlistSessionArgs
          ? null
          : AppRoutes.songTrainerSetlists,
      builder: (_, state) => Consumer(
        builder: (context, ref, _) => buildSetlistSessionScreen(
          context,
          ref,
          state.extra! as SetlistSessionArgs,
        ),
      ),
    ),
  ],
);

Widget _app(GoRouter router, {required bool songTrainerEnabled}) =>
    ProviderScope(
      overrides: <Override>[
        ...preferenceOverrides(),
        appConfigProvider.overrideWithValue(_config(songTrainerEnabled)),
        setlistRepositoryProvider.overrideWithValue(_FakeSetlistRepository()),
        songRepositoryProvider.overrideWithValue(InMemorySongRepository()),
      ],
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );

AppConfig _config(bool songTrainerEnabled) => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    songTrainerV2Enabled: songTrainerEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

final class _FakeSetlistRepository implements SetlistRepository {
  @override
  Future<AppResult<List<SongSetlist>>> list() async =>
      AppResult<List<SongSetlist>>.success(<SongSetlist>[_setlist()]);

  @override
  Future<AppResult<void>> save(SongSetlist setlist) async =>
      const AppResult<void>.success(null);

  @override
  Future<AppResult<void>> delete(String id) async =>
      const AppResult<void>.success(null);

  @override
  Future<AppResult<SongSetlist?>> get(String id) async =>
      AppResult<SongSetlist?>.success(id == 'setlist-1' ? _setlist() : null);
}

SongSetlist _setlist() {
  final now = DateTime.utc(2026, 9, 6);
  return SongSetlist(
    id: 'setlist-1',
    name: 'Saturday gig',
    createdAt: now,
    updatedAt: now,
    items: <SongSetlistItem>[
      SongSetlistItem(id: 'item-1', songId: SongId('song')),
    ],
  );
}
