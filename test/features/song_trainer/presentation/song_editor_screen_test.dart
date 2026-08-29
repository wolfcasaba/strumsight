import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_editor_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart';

void main() {
  test('editor screen retains the route document identifier', () {
    const screen = SongEditorScreen(songId: 'song-42');
    expect(screen.songId, 'song-42');
  });

  testWidgets(
    'editor sends selected measure event, marker, and backing edits',
    (tester) async {
      final repository = InMemorySongRepository();
      final assetRepository = _RecordingAssetRepository();
      final document = _document('editor');
      await repository.create(document);
      final container = ProviderContainer(
        overrides: [
          songRepositoryProvider.overrideWithValue(repository),
          songAssetRepositoryProvider.overrideWithValue(assetRepository),
          songFilePickerAdapterProvider.overrideWithValue(_BackingPicker()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SongEditorScreen(songId: 'editor'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('song-editor-measure')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('song-editor-chord')), 'Dm');
      await tester.tap(find.byKey(const Key('song-editor-add-chord')));
      await tester.tap(find.byKey(const Key('song-editor-add-chord')));
      final tempo = find.byKey(const Key('song-editor-tempo'));
      await tester.ensureVisible(tempo);
      await tester.enterText(tempo, '140');
      final setTempo = find.byKey(const Key('song-editor-set-tempo'));
      await tester.ensureVisible(setTempo);
      await tester.tap(setTempo);
      final meterNumerator = find.byKey(
        const Key('song-editor-meter-numerator'),
      );
      await tester.ensureVisible(meterNumerator);
      await tester.enterText(meterNumerator, '3');
      final setMeter = find.byKey(const Key('song-editor-set-meter'));
      await tester.ensureVisible(setMeter);
      await tester.tap(setMeter);
      final note = find.byKey(const Key('song-editor-note'));
      await tester.ensureVisible(note);
      await tester.enterText(note, '62');
      final addNote = find.byKey(const Key('song-editor-add-note'));
      await tester.ensureVisible(addNote);
      await tester.tap(addNote);
      final attachBacking = find.byKey(const Key('song-editor-attach-backing'));
      await tester.ensureVisible(attachBacking);
      await tester.tap(attachBacking);
      await tester.pumpAndSettle();

      final state = container
          .read(songEditorControllerProvider(SongId('editor')))
          .state;
      final chords = state.draft!.tracks.whereType<ChordTrack>().single.events;
      expect(chords, hasLength(2));
      expect(chords.every((event) => event.symbol.label == 'Dm'), isTrue);
      expect(
        chords.every((event) => event.start == const Duration(seconds: 4)),
        isTrue,
      );
      expect(state.draft!.tempoMap.changes.last.bpm.bpm, 140);
      expect(state.draft!.meterMap.changes.last.meter.numerator, 3);
      expect(
        state.draft!.tracks
            .whereType<NoteTrack>()
            .single
            .events
            .single
            .midiPitch,
        62,
      );
      expect(state.draft!.tracks.whereType<BackingAudioTrack>(), hasLength(1));
      expect(assetRepository.putCalls, 1);
    },
  );

  for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
    testWidgets('remains overflow-free at 200 percent text scale — '
        '${locale.languageCode} locale', (tester) async {
      final repository = InMemorySongRepository();
      final assetRepository = _RecordingAssetRepository();
      final document = _document('editor-scale-${locale.languageCode}');
      await repository.create(document);
      final container = ProviderContainer(
        overrides: [
          songRepositoryProvider.overrideWithValue(repository),
          songAssetRepositoryProvider.overrideWithValue(assetRepository),
          songFilePickerAdapterProvider.overrideWithValue(_BackingPicker()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: SsLightTheme.data(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SongEditorScreen(songId: document.id.value),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('song-editor-measure')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'loading editor renders the design-system skeleton, not a raw spinner',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          songRepositoryProvider.overrideWithValue(_PendingGetRepository()),
          songAssetRepositoryProvider.overrideWithValue(
            _RecordingAssetRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SongEditorScreen(songId: 'missing'),
          ),
        ),
      );
      await tester.pump();

      // A2 guard: `_EditorLoading` must be built from `SsSkeleton`, never a
      // raw `CircularProgressIndicator`.
      expect(find.byType(SsSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'failed editor load renders the design-system danger token, not a raw style',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          songRepositoryProvider.overrideWithValue(_FailingGetRepository()),
          songAssetRepositoryProvider.overrideWithValue(
            _RecordingAssetRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SongEditorScreen(songId: 'missing'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A2 guard: `_EditorLoadError` must render through the design-system
      // danger color token, not a raw default `Text` style.
      final messageFinder = find.byKey(const Key('song-editor-load-error'));
      expect(messageFinder, findsOneWidget);
      final colors = Theme.of(
        tester.element(messageFinder),
      ).extension<SsColorScheme>()!;
      final messageText = tester.widget<Text>(messageFinder);
      expect(messageText.style?.color, colors.danger);
    },
  );
}

SongDocument _document(String id) {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId(id),
    revision: 0,
    metadata: SongMetadata(title: id),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: '$id.song',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
      SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
  );
}

final class _RecordingAssetRepository implements SongAssetRepository {
  var putCalls = 0;

  @override
  Future<AppResult<SongAssetStoreReceipt>> put(
    SongAssetWriteRequest request,
  ) async {
    putCalls++;
    return AppResult<SongAssetStoreReceipt>.success(
      SongAssetStoreReceipt(
        assetId: request.assetId,
        sha256: request.expectedSha256,
        byteLength: request.bytes.length,
        duplicate: false,
      ),
    );
  }

  @override
  Future<AppResult<Uint8List?>> get(String sha256) async =>
      const AppResult<Uint8List?>.success(null);
  @override
  Future<AppResult<SongAssetSummary?>> summary(String sha256) async =>
      const AppResult<SongAssetSummary?>.success(null);
  @override
  Future<AppResult<void>> incrementReference(SongAssetHolder holder) async =>
      const AppResult<void>.success(null);
  @override
  Future<AppResult<void>> decrementReference(SongAssetHolder holder) async =>
      const AppResult<void>.success(null);
  @override
  Future<AppResult<void>> permanentlyDelete(String sha256) async =>
      const AppResult<void>.success(null);
}

final class _BackingPicker implements FilePickerAdapter {
  @override
  Future<void> dispose() async {}

  @override
  Future<ImportSourceFile?> pickSongFile() async => ImportSourceFile(
    displayName: 'backing.mp3',
    byteLength: 1,
    mimeType: 'audio/mpeg',
    openRead: () => Stream<List<int>>.value(<int>[1]),
  );
}

/// `get()` never resolves, so the editor controller stays on
/// `SongEditorStatus.loading` for the lifetime of the test.
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
