import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/learn/audio/chord_audition.dart';
import 'package:strumsight/features/learn/providers/chord_audition_provider.dart';
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
import 'package:strumsight/features/song_trainer/presentation/screens/song_editor_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Records every chord it was asked to strum — the same "hear it" seam used
/// by both the Add-chord flow and the dedicated hear-chord button (ADR 0535).
final class _RecordingAudition implements ChordAudition {
  final List<String> strummed = [];

  @override
  Future<void> strum(
    String label, {
    StrumDirection direction = StrumDirection.down,
  }) async {
    strummed.add(label);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Override _auditionOverride(_RecordingAudition fake) =>
    chordAuditionProvider.overrideWith((ref) {
      ref.onDispose(fake.dispose);
      return fake;
    });

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

void main() {
  testWidgets(
    'adding a chord strums it once; the hear-chord button strums again '
    'without adding a second event',
    (tester) async {
      final repository = InMemorySongRepository();
      final assetRepository = _RecordingAssetRepository();
      final document = _document('editor-audition');
      await repository.create(document);
      final fake = _RecordingAudition();
      final container = ProviderContainer(
        overrides: [
          songRepositoryProvider.overrideWithValue(repository),
          songAssetRepositoryProvider.overrideWithValue(assetRepository),
          songFilePickerAdapterProvider.overrideWithValue(_BackingPicker()),
          _auditionOverride(fake),
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
            home: const SongEditorScreen(songId: 'editor-audition'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('song-editor-chord')), 'Dm');
      await tester.tap(find.byKey(const Key('song-editor-add-chord')));
      await tester.pumpAndSettle();

      expect(fake.strummed, ['Dm']);

      final hear = find.byKey(const Key('song-editor-hear-chord'));
      await tester.ensureVisible(hear);
      await tester.tap(hear);
      await tester.pumpAndSettle();

      expect(fake.strummed, ['Dm', 'Dm']);

      final controller = container.read(
        songEditorControllerProvider(SongId('editor-audition')),
      );
      final draft = controller.state.draft!;
      final chords = draft.tracks.whereType<ChordTrack>().single.events;
      expect(chords, hasLength(1));
      expect(chords.single.symbol.label, 'Dm');
    },
  );
}
