import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_controller.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_state.dart';
import 'package:strumsight/features/song_trainer/data/importers/importer_registry.dart';
import 'package:strumsight/features/song_trainer/data/importers/native_json_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';

void main() {
  test(
    'confirmed native import validates and commits exactly one record',
    () async {
      final root = await Directory.systemTemp.createTemp('song-import-flow-');
      addTearDown(() => root.delete(recursive: true));
      final repository = InMemorySongRepository(clock: DateTime.now);
      final controller = SongImportController(
        registry: const ImporterRegistry(
          importers: <SongImporter>[NativeJsonImporter()],
        ),
        repository: repository,
        workspaceRoot: () async => root,
      );
      addTearDown(controller.dispose);
      final phases = <SongImportPhase>[];
      final stateSubscription = controller.states.listen(
        (state) => phases.add(state.phase),
      );
      addTearDown(stateSubscription.cancel);
      final bytes = await File(
        'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
      ).readAsBytes();

      controller.requestSelection();
      await controller.selectSource(
        ImportSourceFile(
          displayName: 'full_song.strumsight-song.json',
          byteLength: bytes.length,
          openRead: () => Stream<List<int>>.value(bytes),
        ),
      );
      expect(controller.state.phase, SongImportPhase.preview);

      await controller.confirmPreview();

      expect(controller.state.phase, SongImportPhase.success);
      expect(phases, <SongImportPhase>[
        SongImportPhase.selecting,
        SongImportPhase.probing,
        SongImportPhase.preview,
        SongImportPhase.importing,
        SongImportPhase.validating,
        SongImportPhase.committing,
        SongImportPhase.success,
      ]);
      final records = await repository.list(const SongQuery());
      expect(records, isA<Success<List<SongSummary>>>());
      expect((records as Success<List<SongSummary>>).value, hasLength(1));
      expect(await root.list().toList(), isEmpty);
    },
  );
}
