// A1/A2 — the import preview commits nothing on its own, and a cancelled
// import leaves no temporary file behind (ADR 0284 §Döntés 1 + §Döntés 2).
//
//   A1 — reaching `SongImportPhase.preview` must not create any repository
//        record and must not write to the injected workspace root.
//   A2 — cancelling a CONFIRMED import (after `ImportWorkspace.open` has
//        already run inside `confirmPreview()`, per round brief §0.0/B/R12)
//        leaves the injected temp root empty once the cancellation settles.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_controller.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_state.dart';
import 'package:strumsight/features/song_trainer/data/importers/importer_registry.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';

void main() {
  test('A1: reaching the preview creates no persistent record and writes no '
      'temp file', () async {
    final repository = InMemorySongRepository();
    final tempRoot = await Directory.systemTemp.createTemp('e13r24-a1-');
    addTearDown(() => tempRoot.delete(recursive: true));
    final controller = SongImportController(
      registry: ImporterRegistry(
        importers: <SongImporter>[_ImmediateImporter(_validDocument('a1'))],
      ),
      repository: repository,
      workspaceRoot: () async => tempRoot,
    );
    addTearDown(controller.dispose);

    controller.requestSelection();
    await controller.selectSource(_fakeSource('song.musicxml'));

    expect(controller.state.phase, SongImportPhase.preview);

    final listed = await repository.list(const SongQuery());
    expect((listed as Success<List<SongSummary>>).value, isEmpty);
    // `confirmPreview()` is what opens `ImportWorkspace`, and preview alone
    // never calls it — the injected temp root must still be untouched.
    expect(tempRoot.listSync(), isEmpty);
  });

  test(
    'A2: cancelling a confirmed import cleans the opened workspace',
    () async {
      final repository = InMemorySongRepository();
      final tempRoot = await Directory.systemTemp.createTemp('e13r24-a2-');
      addTearDown(() => tempRoot.delete(recursive: true));
      final gate = Completer<void>();
      final controller = SongImportController(
        registry: ImporterRegistry(
          importers: <SongImporter>[
            _GatedImporter(_validDocument('a2'), gate.future),
          ],
        ),
        repository: repository,
        workspaceRoot: () async => tempRoot,
      );
      addTearDown(controller.dispose);

      controller.requestSelection();
      await controller.selectSource(_fakeSource('song.musicxml'));
      expect(controller.state.phase, SongImportPhase.preview);

      final confirmFuture = controller.confirmPreview();
      // Let `confirmPreview()` run up to the point where it awaits the gated
      // `import()` call — the workspace has opened by then (R12: it opens
      // BEFORE `registry.import` runs).
      await pumpEventQueue();
      expect(controller.state.phase, SongImportPhase.importing);
      expect(tempRoot.listSync(), isNotEmpty);

      await controller.cancel();

      expect(controller.state.phase, SongImportPhase.cancelled);
      expect(
        tempRoot.listSync(),
        isEmpty,
        reason: 'A2: a cancelled import must not leave a temp file behind',
      );

      // Release the still-pending import() so its Future resolves cleanly —
      // by then the operation is detached and the result is discarded.
      gate.complete();
      await confirmFuture;
      expect(tempRoot.listSync(), isEmpty);
    },
  );
}

SongDocument _validDocument(String id) {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId(id),
    revision: 0,
    metadata: SongMetadata(title: id),
    source: SongSource(
      type: SongSourceType.musicXml,
      originalFileName: '$id.musicxml',
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
  );
}

ImportSourceFile _fakeSource(String name) => ImportSourceFile(
  displayName: name,
  byteLength: 4,
  openRead: () => Stream<List<int>>.value(<int>[1, 2, 3, 4]),
);

/// Recognises and imports instantly — used for the A1 cell, which never
/// reaches `confirmPreview()`.
final class _ImmediateImporter implements SongImporter {
  _ImmediateImporter(this._document);

  final SongDocument _document;

  @override
  Set<String> get supportedExtensions => const <String>{'musicxml'};

  @override
  Future<ImportProbeResult> probe(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  ) async => const ImportProbeResult.recognized();

  @override
  Future<AppResult<SongImportResult>> import(
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken cancellationToken,
  ) async => AppResult<SongImportResult>.success(
    SongImportResult(document: _document),
  );
}

/// Recognises instantly but `import()` blocks on [gate] — lets the A2 cell
/// observe the `importing` phase (workspace already open) before cancelling.
final class _GatedImporter implements SongImporter {
  _GatedImporter(this._document, this._gate);

  final SongDocument _document;
  final Future<void> _gate;

  @override
  Set<String> get supportedExtensions => const <String>{'musicxml'};

  @override
  Future<ImportProbeResult> probe(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  ) async => const ImportProbeResult.recognized();

  @override
  Future<AppResult<SongImportResult>> import(
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken cancellationToken,
  ) async {
    await _gate;
    return AppResult<SongImportResult>.success(
      SongImportResult(document: _document),
    );
  }
}
