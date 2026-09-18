// A2b — the two `extra`-carrying Song Trainer routes must guard their
// payload the same way every other such route in `app_router.dart` does
// (`librarySession`, `profileLibrarySession`, `analysisOverview`,
// `analysisTimeline`, `analysisCompare`). Before the guard,
// `state.extra! as SongTrainerControllerInputs` / `as SongTrainerResult`
// turned a deep link, a restored URL or a process-death relaunch into a
// null-check crash instead of landing the user somewhere deliberate.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_overview_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_result_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

const String _songId = 'guarded-song';

SongDocument _document(String id) {
  final now = DateTime.utc(2026, 9, 18);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId(id),
    revision: 0,
    metadata: SongMetadata(title: id),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: '$id.song',
      sha256: 'b' * 64,
      importedAt: now,
      importerVersion: 'guard-test@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
  );
}

Future<GoRouter> _pumpRouterTo(
  WidgetTester tester,
  String location, {
  Object? extra,
}) async {
  final engine = FakeStrumEngine();
  final songRepository = InMemorySongRepository();
  await songRepository.create(_document(_songId));

  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(engine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      songRepositoryProvider.overrideWithValue(songRepository),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            songTrainerV2Enabled: true,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  final router = container.read(routerProvider);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await engine.dispose();
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

  router.go(location, extra: extra);
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('a session deep link without inputs lands on the song overview, '
      'not on a null-check crash', (tester) async {
    final router = await _pumpRouterTo(
      tester,
      AppRoutes.songTrainerSession.replaceFirst(':songId', _songId),
    );

    expect(tester.takeException(), isNull);
    expect(
      router.state.uri.path,
      AppRoutes.songTrainerOverview.replaceFirst(':songId', _songId),
    );
    expect(find.byType(SongOverviewScreen), findsOneWidget);
    expect(find.byType(SongTrainerScreen), findsNothing);
  });

  testWidgets('a result deep link without a result lands on the song overview, '
      'not on a null-check crash', (tester) async {
    final router = await _pumpRouterTo(
      tester,
      AppRoutes.songTrainerResult.replaceFirst(':songId', _songId),
    );

    expect(tester.takeException(), isNull);
    expect(
      router.state.uri.path,
      AppRoutes.songTrainerOverview.replaceFirst(':songId', _songId),
    );
    expect(find.byType(SongOverviewScreen), findsOneWidget);
    expect(find.byType(SongResultScreen), findsNothing);
  });

  testWidgets(
    'a session deep link carrying a wrong-typed extra also lands on the '
    'song overview',
    (tester) async {
      final router = await _pumpRouterTo(
        tester,
        AppRoutes.songTrainerSession.replaceFirst(':songId', _songId),
        extra: 'not-the-inputs-object',
      );

      expect(tester.takeException(), isNull);
      expect(
        router.state.uri.path,
        AppRoutes.songTrainerOverview.replaceFirst(':songId', _songId),
      );
      expect(find.byType(SongTrainerScreen), findsNothing);
    },
  );
}
