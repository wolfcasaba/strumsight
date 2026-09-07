// R18 (audit B4) — the Songs tab's entry into the Song Trainer V2 library.
//
// MEASURED before this round: `/song-trainer` (and the seven Song Trainer
// screens behind it) had exactly ONE caller in `lib/` — `LessonListScreen` —
// and nothing in the shipped adaptive shell opened THAT either, so the whole
// Song Trainer surface was unreachable by touch. The Songs destination now
// carries an AppBar action into it, gated by the SAME flag as the route
// (`songTrainerV2Enabled`), so the control can never point at a route the
// router did not register.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/songs/screens/song_list_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

const _entryKey = Key('song-list-open-song-trainer');

Future<GoRouter> _pumpSongs(
  WidgetTester tester, {
  required bool songTrainerV2Enabled,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.songs,
    routes: [
      GoRoute(
        // The screen under test — the adaptive shell's Songs destination.
        path: AppRoutes.songs,
        builder: (_, _) => const SongListScreen(),
      ),
      GoRoute(
        path: AppRoutes.songTrainerLibrary,
        builder: (_, state) => Scaffold(body: Text('STUB ${state.uri.path}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...preferenceOverrides(),
        appConfigProvider.overrideWithValue(
          AppConfig(
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
          ),
        ),
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
  return router;
}

void main() {
  testWidgets('the Songs tab opens the Song Trainer library', (tester) async {
    final router = await _pumpSongs(tester, songTrainerV2Enabled: true);

    expect(find.byKey(_entryKey), findsOneWidget);
    await tester.tap(find.byKey(_entryKey));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.songTrainerLibrary);
    expect(find.text('STUB ${AppRoutes.songTrainerLibrary}'), findsOneWidget);
  });

  testWidgets('the entry can be popped back to the songbook — it is pushed, '
      'not a stack-replacing go', (tester) async {
    final router = await _pumpSongs(tester, songTrainerV2Enabled: true);

    await tester.tap(find.byKey(_entryKey));
    await tester.pumpAndSettle();
    expect(router.canPop(), isTrue);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(SongListScreen), findsOneWidget);
  });

  testWidgets('with songTrainerV2Enabled off the entry is absent — the route '
      'is not registered in that build either', (tester) async {
    await _pumpSongs(tester, songTrainerV2Enabled: false);

    expect(find.byKey(_entryKey), findsNothing);
    // Control: the screen itself rendered, so the missing action is the
    // gate, not a screen that failed to build.
    expect(find.byType(SongListScreen), findsOneWidget);
  });
}
