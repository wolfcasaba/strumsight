import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/tuning.dart';
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
import 'package:strumsight/features/song_trainer/domain/models/trainer_config.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/trainer_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

void main() {
  testWidgets(
    'shows unavailable pitch honestly, tuning/capo reminders, and returns one config',
    (tester) async {
      final repository = InMemorySongRepository();
      final document = _document();
      TrainerConfig? completed;
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
            home: TrainerSetupScreen(
              songId: document.id.value,
              onComplete: (config) => completed = config,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        container
            .read(songTrainerSetupControllerProvider(document.id))
            .state
            .config!
            .tuningReminder,
        Tunings.dropD,
      );

      final pitch = tester.widget<RadioListTile<TrainerMode>>(
        find.byKey(const Key('trainer-mode-pitch')),
      );
      expect(pitch.enabled, isFalse);
      await tester.scrollUntilVisible(
        find.byKey(const Key('trainer-tuning-reminder')),
        300,
      );
      expect(find.byKey(const Key('trainer-tuning-reminder')), findsOneWidget);
      expect(find.byKey(const Key('trainer-capo-reminder')), findsOneWidget);
      expect(
        find.byKey(const Key('trainer-backing-rate-pending')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('trainer-setup-start')),
        300,
      );
      await tester.tap(find.byKey(const Key('trainer-setup-start')));
      await tester.pump();

      expect(completed, isNotNull);
      expect(completed!.songId, document.id);
      expect(completed!.capo, 2);
      expect(completed!.capoReminder, isTrue);
      expect(completed!.tuningReminder, Tunings.dropD);
      expect((await repository.get(document.id)).valueOrNull, document);
    },
  );

  testWidgets('remains scrollable at 200 percent text scale', (tester) async {
    final repository = InMemorySongRepository();
    final document = _document();
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
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: TrainerSetupScreen(songId: document.id.value),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('trainer-setup-start')),
      400,
    );
    expect(find.byKey(const Key('trainer-setup-start')), findsOneWidget);
  });
}

SongDocument _document() {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('setup'),
    revision: 0,
    metadata: SongMetadata(
      title: 'Setup song',
      defaultTuning: Tunings.dropD,
      defaultCapo: 2,
    ),
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
