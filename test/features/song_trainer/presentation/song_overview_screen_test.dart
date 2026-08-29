import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
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
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_overview_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart';

void main() {
  testWidgets('shows song identity, selectable sections, and trainer entry', (
    tester,
  ) async {
    final repository = InMemorySongRepository();
    final document = _document();
    await repository.create(document);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [songRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SongOverviewScreen(songId: document.id.value),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Overview song'), findsOneWidget);
    expect(find.text('Verse'), findsOneWidget);
    expect(
      find.byKey(const Key('song-overview-section-verse')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('song-overview-start')), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const Key('song-overview-start'))).label,
      contains('Set up trainer'),
    );
  });

  for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
    testWidgets(
      'remains overflow-free at 200 percent text scale — ${locale.languageCode} locale',
      (tester) async {
        final repository = InMemorySongRepository();
        final document = _document();
        await repository.create(document);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [songRepositoryProvider.overrideWithValue(repository)],
            child: MaterialApp(
              theme: SsLightTheme.data(),
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SongOverviewScreen(songId: document.id.value),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.byKey(const Key('song-overview-start')),
          300,
        );
        expect(find.byKey(const Key('song-overview-start')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'loading overview renders the design-system skeleton, not a raw spinner',
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
            home: const SongOverviewScreen(songId: 'missing'),
          ),
        ),
      );
      await tester.pump();

      // A2 guard: `_OverviewLoading` must be built from `SsSkeleton`, never a
      // raw `CircularProgressIndicator`.
      expect(find.byType(SsSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('failed overview load renders the design-system retry button', (
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
          home: const SongOverviewScreen(songId: 'missing'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A2 guard: `_OverviewError` must render its retry action through
    // `SsButton` (which itself composes a `FilledButton`) — a bare
    // `TextButton`/`ElevatedButton` fallback would leave `SsButton` absent.
    expect(find.byType(SsButton), findsOneWidget);
  });
}

SongDocument _document() {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('overview'),
    revision: 0,
    metadata: SongMetadata(title: 'Overview song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'overview.song',
      sha256: 'a' * 64,
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
