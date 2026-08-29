// A6 — an orientation change preserves the trainer setup selections (loop
// toggle, target speed) instead of resetting the form.
// A8 — an invalid measure-range/speed setup is rejected; the previous valid
// configuration survives instead of handing the Stage a broken config.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_setup_controller.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/trainer_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

void main() {
  group('A6 — orientation change preserves trainer setup selections', () {
    testWidgets(
      'loop toggle and target speed survive a portrait/landscape switch',
      (tester) async {
        final repository = InMemorySongRepository();
        final document = _document();
        await repository.create(document);
        final container = ProviderContainer(
          overrides: [songRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: TrainerSetupScreen(songId: document.id.value),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final controller = container.read(
          songTrainerSetupControllerProvider(document.id),
        );
        await tester.tap(find.byKey(const Key('trainer-loop')));
        await tester.pump();
        controller.setTargetSpeed(0.75);
        await tester.pump();

        expect(controller.state.config!.loopConfig.maxRepeats, isNotNull);
        expect(controller.state.config!.targetSpeed, 0.75);

        // Rotate to landscape — a pure MediaQuery/constraints change; the
        // route-scoped controller must not be recreated by it.
        tester.view.physicalSize = const Size(800, 400);
        await tester.pumpAndSettle();

        expect(
          identical(
            controller,
            container.read(songTrainerSetupControllerProvider(document.id)),
          ),
          isTrue,
        );
        expect(controller.state.config!.loopConfig.maxRepeats, isNotNull);
        expect(controller.state.config!.targetSpeed, 0.75);
        await tester.scrollUntilVisible(
          find.byKey(const Key('trainer-setup-start')),
          400,
        );
        expect(find.byKey(const Key('trainer-setup-start')), findsOneWidget);
      },
    );
  });

  group('A8 — invalid section/speed setups are rejected', () {
    testWidgets(
      'an inverted measure range is rejected and the previous valid config '
      'survives instead of handing Start a broken TrainerConfig',
      (tester) async {
        final repository = InMemorySongRepository();
        final document = _document(measureCount: 8);
        await repository.create(document);
        final container = ProviderContainer(
          overrides: [songRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: TrainerSetupScreen(songId: document.id.value),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final controller = container.read(
          songTrainerSetupControllerProvider(document.id),
        );
        final validConfigBefore = controller.state.config;
        expect(validConfigBefore, isNotNull);

        await tester.tap(find.byKey(const Key('trainer-range-kind')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Measures').last);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('trainer-range-start')),
          '5',
        );
        await tester.enterText(find.byKey(const Key('trainer-range-end')), '2');
        await tester.tap(find.byKey(const Key('trainer-range-apply')));
        await tester.pump();

        expect(
          find.text('Choose a valid range inside this song.'),
          findsOneWidget,
        );
        // The rejected input must not have mutated the surfaced config — the
        // Stage still receives the last valid selection, never a broken one.
        expect(controller.state.config, validConfigBefore);

        final startButton = tester.widget<FilledButton>(
          find.byKey(const Key('trainer-setup-start')),
        );
        expect(startButton.onPressed, isNotNull);
      },
    );

    testWidgets(
      'an out-of-bounds measure range (end beyond the song) is rejected',
      (tester) async {
        final repository = InMemorySongRepository();
        final document = _document(measureCount: 4);
        await repository.create(document);
        final container = ProviderContainer(
          overrides: [songRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: TrainerSetupScreen(songId: document.id.value),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final controller = container.read(
          songTrainerSetupControllerProvider(document.id),
        );
        final validConfigBefore = controller.state.config;

        await tester.tap(find.byKey(const Key('trainer-range-kind')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Measures').last);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('trainer-range-start')),
          '1',
        );
        await tester.enterText(
          find.byKey(const Key('trainer-range-end')),
          '99',
        );
        await tester.tap(find.byKey(const Key('trainer-range-apply')));
        await tester.pump();

        expect(
          find.text('Choose a valid range inside this song.'),
          findsOneWidget,
        );
        expect(controller.state.config, validConfigBefore);
      },
    );
  });
}

SongDocument _document({int measureCount = 4}) {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('setup-a6-a8'),
    revision: 0,
    metadata: SongMetadata(title: 'Setup song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'setup.song',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      for (var index = 0; index < measureCount; index++)
        SongMeasure(index: index, durationBeats: BeatPosition.fromBeats(4)),
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
