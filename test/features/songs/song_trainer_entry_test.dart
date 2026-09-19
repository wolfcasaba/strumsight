// E18-R01 emulator finding F8 — the V2 Song Trainer (library → editor) was
// unreachable from the four-tab shell: its only entry sat on the Learn
// lesson list, which the shell never links to. The Songs tab now carries a
// flag-gated entry that PUSHES the trainer library (so back returns).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/features/songs/screens/song_list_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

const _entryKey = Key('songs-entry-song-trainer');

AppConfig _config({required bool songTrainerV2Enabled}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: true,
    labModeAvailable: true,
    songTrainerV2Enabled: songTrainerV2Enabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Future<GoRouter> _pumpSongs(
  WidgetTester tester, {
  required bool songTrainerV2Enabled,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.songs,
    routes: [
      GoRoute(path: AppRoutes.songs, builder: (_, _) => const SongListScreen()),
      GoRoute(
        path: AppRoutes.songTrainerLibrary,
        builder: (_, _) => const Scaffold(body: Text('trainer library')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        appConfigProvider.overrideWithValue(
          _config(songTrainerV2Enabled: songTrainerV2Enabled),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('flag ON: the Songs tab opens the Song Trainer library, pushed', (
    tester,
  ) async {
    final router = await _pumpSongs(tester, songTrainerV2Enabled: true);
    expect(find.byKey(_entryKey), findsOneWidget);

    await tester.tap(find.byKey(_entryKey));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.songTrainerLibrary);
    expect(find.text('trainer library'), findsOneWidget);
    // Pushed, not replaced: back returns to the Songs tab.
    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(SongListScreen), findsOneWidget);
  });

  testWidgets('flag OFF: no entry at all (the routes are not registered '
      'either)', (tester) async {
    await _pumpSongs(tester, songTrainerV2Enabled: false);
    expect(find.byKey(_entryKey), findsNothing);
  });
}
