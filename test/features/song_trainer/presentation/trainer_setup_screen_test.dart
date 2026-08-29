import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
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
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/trainer_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart';

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
    expect(tester.takeException(), isNull);
  });

  testWidgets('remains scrollable at 200 percent text scale — hu locale', (
    tester,
  ) async {
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
          locale: const Locale('hu'),
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
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading setup renders the design-system skeleton, not a raw spinner',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            songRepositoryProvider.overrideWithValue(_PendingGetRepository()),
          ],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TrainerSetupScreen(songId: 'missing'),
          ),
        ),
      );
      await tester.pump();

      // A2 guard: `_SetupLoading` must be built from `SsSkeleton`, never a
      // raw `CircularProgressIndicator`.
      expect(find.byType(SsSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('failed setup load renders the design-system retry button', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          songRepositoryProvider.overrideWithValue(_FailingGetRepository()),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const TrainerSetupScreen(songId: 'missing'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A2 guard: `_SetupError` must render its retry action through
    // `SsButton` (which itself composes a `FilledButton`) — a bare
    // `TextButton`/`ElevatedButton` fallback would leave `SsButton` absent.
    expect(find.byType(SsButton), findsOneWidget);
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

/// `get()` never resolves, so the setup controller stays on
/// `SongTrainerSetupStatus.loading` for the lifetime of the test.
final class _PendingGetRepository implements SongRepository {
  final _pending = Completer<AppResult<SongDocument?>>();

  @override
  Future<AppResult<SongDocument?>> get(SongId id) => _pending.future;

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> create(SongDocument document) =>
      throw UnimplementedError();

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

final class _FailingGetRepository implements SongRepository {
  @override
  Future<AppResult<SongDocument?>> get(SongId id) async =>
      AppResult<SongDocument?>.failure(
        const StorageFailure(code: SongRepositoryErrorCode.notFound),
      );

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> create(SongDocument document) =>
      throw UnimplementedError();

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
