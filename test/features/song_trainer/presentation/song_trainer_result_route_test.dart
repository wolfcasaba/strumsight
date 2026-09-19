// WP-H1 — a `songTrainerResult` útvonal BEJÖVŐ hivatkozása.
//
// A vezérlő a pontozott munkamenet végén `NavigateToSongTrainerResult`
// effektust bocsát ki. A körig ezt SENKI nem hallgatta (mérve: az
// `AppRoutes.songTrainerResult` konstansra egyetlen navigáció sem mutatott a
// `lib/`-ben), így az eredmény megszületett, de sosem jelent meg. Ez a fájl a
// két lépést méri: az effektus az eredmény-útvonalra navigál a MÉRT
// eredménnyel `extra`-ként, és a munkamenet ezután a hívónak is visszaadja —
// ezen múlik, hogy egy dalcsomag-tétel `completed`-ként zárul-e.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_practice_compiler.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_controller.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/loop_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart'
    as song_time;
import 'package:strumsight/features/song_trainer/domain/models/trainer_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_range.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/setlists/setlist_session_entry.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_practice_observation_gateway.dart';
import '../../../support/fake_practice_session_clock.dart';
import '../../../support/fake_practice_session_recorder.dart';
import '../../../support/fake_practice_tick_source.dart';
import '../../../support/preference_store.dart';

void main() {
  testWidgets('a finalised scored session navigates to the result route with '
      'the mapped result and hands it back to the caller', (tester) async {
    final harness = _Harness.scored();
    addTearDown(harness.dispose);
    final inputs = SongTrainerControllerInputs(
      compilation: harness.compilation,
    );
    SongTrainerResult? handedBack;
    var pushes = 0;

    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('open-session'),
                onPressed: () async {
                  pushes++;
                  handedBack = await context.push<SongTrainerResult>(
                    songTrainerSessionLocation('song'),
                    extra: inputs,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.songTrainerSession,
          builder: (_, state) => SongTrainerScreen(
            songId: state.pathParameters['songId']!,
            inputs: state.extra! as SongTrainerControllerInputs,
          ),
        ),
        GoRoute(
          path: AppRoutes.songTrainerResult,
          builder: (_, state) =>
              _ResultProbe(result: state.extra! as SongTrainerResult),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...preferenceOverrides(),
          songTrainerControllerProvider(
            inputs,
          ).overrideWith((ref) => harness.controller),
        ],
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

    await tester.tap(find.byKey(const Key('open-session')));
    await tester.pumpAndSettle();
    expect(pushes, 1);
    expect(find.byType(SongTrainerScreen), findsOneWidget);

    // Run the scored session to its terminal state — this is what emits the
    // effect nothing used to listen to.
    await harness.controller.prepare();
    await harness.controller.start();
    harness.practiceTick.emitTick();
    await tester.pumpAndSettle();
    final finishing = harness.controller.finish();
    harness.practiceTick.emitTick();
    await tester.pumpAndSettle();
    await finishing;
    await tester.pumpAndSettle();

    // ignore: avoid_print
    print('DIAG status=${harness.controller.state.status} result=${harness.controller.state.result} loc=${router.state.uri.path}');
    expect(
      find.byType(_ResultProbe),
      findsOneWidget,
      reason: 'the effect must navigate to the result route',
    );
    final probe = tester.widget<_ResultProbe>(find.byType(_ResultProbe));
    expect(
      probe.result,
      same(harness.controller.state.result),
      reason: 'the route receives the MAPPED result as its extra',
    );
    expect(router.state.uri.path, '/song-trainer/result/song');

    // Leaving the result screen returns the run to whoever started it — the
    // setlist item runner awaits exactly this value.
    router.pop();
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/');
    expect(handedBack, isNotNull);
    expect(handedBack, same(probe.result));
  });
}

final class _ResultProbe extends StatelessWidget {
  const _ResultProbe({required this.result});

  final SongTrainerResult result;

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('result')));
}

final class _Harness {
  _Harness._({
    required this.controller,
    required this.transport,
    required this.practiceTick,
    required this.compilation,
  });

  final SongTrainerController controller;
  final SongTransport transport;
  final FakePracticeTickSource practiceTick;
  final SongPracticeCompilation compilation;

  factory _Harness.scored() {
    final compilation = SongPracticeCompiler.compile(
      document: _document(),
      config: _config(),
    );
    final transport = SongTransport(
      player: FakeBackingAudioPlayer(),
      clock: FakeSongTransportClock(),
    );
    final practiceTick = FakePracticeTickSource();
    final practice = PracticeSessionController(
      clock: FakePracticeSessionClock(),
      tickSource: practiceTick,
      recorder: FakePracticeSessionRecorder(),
      logger: const NoopAppLogger(),
      permissions: FakeMicrophonePermissionGateway(),
      observationConfig: const PracticeObservationConfig(),
      sessionIdFactory: () => 'practice-result',
      compileTarget: (definition, config) => Future.value(
        compilePracticeTarget(definition: definition, config: config),
      ),
      observationGateway: FakePracticeObservationGateway(),
    );
    return _Harness._(
      controller: SongTrainerController(
        transport: transport,
        compilation: compilation,
        practiceSession: practice,
      ),
      transport: transport,
      practiceTick: practiceTick,
      compilation: compilation,
    );
  }

  Future<void> dispose() async {
    await controller.dispose();
    await transport.dispose();
  }
}

final SongInstrument _guitar = SongInstrument(name: 'Guitar');

SongDocument _document() {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('song'),
    revision: 1,
    metadata: SongMetadata(title: 'Song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'song.json',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: song_time.BeatPosition.fromBeats(4)),
    ],
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('section'),
        name: 'Section',
        startMeasure: 0,
        endMeasureExclusive: 1,
      ),
    ],
    tempoMap: song_time.TempoMap.constant(song_time.Tempo(120)),
    tracks: <SongTrack>[
      StrumTrack(
        id: SongTrackId('strums'),
        name: 'Strums',
        instrument: _guitar,
        events: <SongStrumEvent>[
          SongStrumEvent(
            id: SongEventId('strum'),
            at: Duration.zero,
            direction: StrumDirection.down,
          ),
        ],
      ),
    ],
  );
}

TrainerConfig _config() {
  final range = MeasureRange(start: 0, endExclusive: 1);
  return TrainerConfig(
    songId: SongId('song'),
    songRevision: 1,
    trackId: SongTrackId('strums'),
    selection: range,
    range: range,
    mode: TrainerMode.rhythm,
    targetSpeed: 1,
    countInBars: 0,
    metronomeEnabled: true,
    loopConfig: LoopConfig(range: range),
    tuningReminder: null,
    capo: 0,
    capoReminder: false,
  );
}
