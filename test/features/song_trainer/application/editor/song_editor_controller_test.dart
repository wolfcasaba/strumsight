import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/editor/editor_history.dart';
import 'package:strumsight/features/song_trainer/application/editor/song_editor_controller.dart';
import 'package:strumsight/features/song_trainer/application/editor/song_editor_state.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';

SongDocument document(String id, {bool invalid = false}) {
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
      importerVersion: 'editor@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
    ],
    sections: invalid
        ? <SongSection>[
            SongSection(
              id: SongSectionId('invalid'),
              name: 'Invalid',
              startMeasure: 0,
              endMeasureExclusive: 2,
            ),
          ]
        : const <SongSection>[],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
  );
}

void main() {
  late InMemorySongRepository repository;
  late SongEditorController controller;

  setUp(() {
    repository = InMemorySongRepository(clock: () => DateTime.utc(2026, 8, 4));
    controller = SongEditorController(
      repository: repository,
      assetRepository: const _AssetRepository(),
      clock: () => DateTime.utc(2026, 8, 4),
    );
  });

  tearDown(() => controller.dispose());

  test('edit, undo and redo restore exact draft snapshots', () async {
    final original = document('undo');
    await repository.create(original);
    await controller.load(original.id);

    controller.editMetadata(SongMetadata(title: 'Changed'));
    expect(controller.state.isDirty, isTrue);
    expect(controller.state.draft!.metadata.title, 'Changed');
    controller.undo();
    expect(controller.state.draft, original);
    controller.redo();
    expect(controller.state.draft!.metadata.title, 'Changed');
  });

  test('new edit after undo clears redo and history stays bounded', () async {
    final original = document('bounded');
    await repository.create(original);
    final bounded = SongEditorController(
      repository: repository,
      assetRepository: const _AssetRepository(),
      history: EditorHistory(limit: 2),
    );
    await bounded.load(original.id);
    bounded.editMetadata(SongMetadata(title: 'one'));
    bounded.editMetadata(SongMetadata(title: 'two'));
    bounded.editMetadata(SongMetadata(title: 'three'));
    bounded.undo();
    bounded.editMetadata(SongMetadata(title: 'replacement'));
    expect(bounded.state.canRedo, isFalse);
    await bounded.dispose();
  });

  test(
    'invalid save does not call repository create and retains draft',
    () async {
      final invalid = document('invalid', invalid: true);
      controller.startNew(invalid);
      await controller.save();

      expect(controller.state.status, SongEditorStatus.validationFailed);
      expect(controller.state.draft, invalid);
      expect((await repository.get(invalid.id)).valueOrNull, isNull);
    },
  );

  test('new valid draft saves through repository create', () async {
    final draft = document('new-draft');
    controller.startNew(draft);

    await controller.save();

    expect(controller.state.isDirty, isFalse);
    expect((await repository.get(draft.id)).valueOrNull, isNotNull);
  });

  test(
    'stale revision retains draft and exposes conflict without overwrite',
    () async {
      final original = document('conflict');
      await repository.create(original);
      await controller.load(original.id);
      await repository.update(original, expectedRevision: 0);
      controller.editMetadata(SongMetadata(title: 'local draft'));

      await controller.save();

      expect(controller.state.status, SongEditorStatus.conflict);
      expect(controller.state.draft!.metadata.title, 'local draft');
      expect(
        (await repository.get(original.id)).valueOrNull!.metadata.title,
        'conflict',
      );
    },
  );

  test('backing asset failure leaves draft reference unchanged', () async {
    final original = document('asset');
    await repository.create(original);
    final failing = SongEditorController(
      repository: repository,
      assetRepository: const _AssetRepository(failPut: true),
    );
    await failing.load(original.id);
    await failing.attachBacking(
      SongAssetWriteRequest(
        bytes: Uint8List.fromList(<int>[1]),
        assetId: SongAssetId('asset'),
        extension: 'mp3',
        expectedSha256: '0' * 64,
      ),
    );
    expect(failing.state.draft!.assets, isEmpty);
    await failing.dispose();
  });

  test(
    'successful backing attachment updates the draft after asset put',
    () async {
      final original = document('asset-success');
      await repository.create(original);
      await controller.load(original.id);

      await controller.attachBacking(
        SongAssetWriteRequest(
          bytes: Uint8List.fromList(<int>[1]),
          assetId: SongAssetId('asset-success'),
          extension: 'mp3',
          expectedSha256: '0' * 64,
        ),
      );

      expect(controller.state.draft!.assets, hasLength(1));
      expect(
        controller.state.draft!.tracks.whereType<BackingAudioTrack>(),
        hasLength(1),
      );
    },
  );
}

final class _AssetRepository implements SongAssetRepository {
  const _AssetRepository({this.failPut = false});
  final bool failPut;

  @override
  Future<AppResult<SongAssetStoreReceipt>> put(
    SongAssetWriteRequest request,
  ) async => failPut
      ? AppResult<SongAssetStoreReceipt>.failure(
          const StorageFailure(code: 'asset.failed'),
        )
      : AppResult<SongAssetStoreReceipt>.success(
          SongAssetStoreReceipt(
            assetId: request.assetId,
            sha256: request.expectedSha256,
            byteLength: request.bytes.length,
            duplicate: false,
          ),
        );

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
