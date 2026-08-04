import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_controller.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_effect.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_state.dart';
import 'package:strumsight/features/song_trainer/data/importers/importer_registry.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';

void main() {
  group('SongImportController', () {
    test(
      'selecting cancellation returns to idle and requests picker cleanup',
      () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        final effects = <SongImportEffect>[];
        final subscription = harness.controller.effects.listen(effects.add);
        addTearDown(subscription.cancel);
        final states = <SongImportState>[];
        final stateSubscription = harness.controller.states.listen(states.add);
        addTearDown(stateSubscription.cancel);

        harness.controller.requestSelection();
        await Future<void>.delayed(Duration.zero);
        await harness.controller.cancel();

        expect(harness.controller.state.phase, SongImportPhase.idle);
        expect(effects, contains(const CleanupFilePickerEffect()));
        expect(states.map((state) => state.phase), <SongImportPhase>[
          SongImportPhase.selecting,
          SongImportPhase.idle,
        ]);
      },
    );

    test(
      'a stale import callback cannot overwrite a newer retry state',
      () async {
        final firstImport = Completer<AppResult<SongImportResult>>();
        final importer = _ControlledImporter(firstImport: firstImport);
        final harness = await _Harness.create(importer: importer);
        addTearDown(harness.dispose);

        harness.controller.requestSelection();
        await harness.controller.selectSource(_source('first.song'));
        final firstOperation = harness.controller.confirmPreview();
        await Future<void>.delayed(Duration.zero);
        await harness.controller.retry();
        final secondOperationId = harness.controller.state.operationId;

        firstImport.complete(
          AppResult<SongImportResult>.success(
            SongImportResult(document: _document()),
          ),
        );
        await firstOperation;

        expect(harness.controller.state.operationId, secondOperationId);
        expect(harness.controller.state.phase, SongImportPhase.selecting);
      },
    );

    test(
      'cancellation during import closes the workspace without a record',
      () async {
        final importer = _ControlledImporter(
          firstImport: Completer<AppResult<SongImportResult>>(),
        );
        final harness = await _Harness.create(importer: importer);
        addTearDown(harness.dispose);
        harness.controller.requestSelection();
        await harness.controller.selectSource(_source('cancelled.song'));
        final importing = harness.controller.confirmPreview();
        await Future<void>.delayed(Duration.zero);

        await harness.controller.cancel();
        importer.firstImport!.complete(
          AppResult<SongImportResult>.success(
            SongImportResult(document: _document()),
          ),
        );

        expect(harness.controller.state.phase, SongImportPhase.cancelled);
        expect(await harness.workspaceRoot.list().toList(), isEmpty);
        final records = await harness.repository.list(const SongQuery());
        expect((records as Success).value, isEmpty);
        await importing;
      },
    );

    test(
      'cancellation while opening a workspace closes the late workspace',
      () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        harness.controller.requestSelection();
        await harness.controller.selectSource(_source('cancelled.song'));

        final importing = harness.controller.confirmPreview();
        await harness.controller.cancel();
        await importing;

        expect(harness.controller.state.phase, SongImportPhase.cancelled);
        expect(await harness.workspaceRoot.list().toList(), isEmpty);
        final records = await harness.repository.list(const SongQuery());
        expect((records as Success).value, isEmpty);
      },
    );

    test(
      'unsupported content fails before a workspace or repository record exists',
      () async {
        final harness = await _Harness.create(
          importer: _ControlledImporter(
            probeResult: const ImportProbeResult.failure(
              'songImport.unsupported',
            ),
          ),
        );
        addTearDown(harness.dispose);

        harness.controller.requestSelection();
        await harness.controller.selectSource(_source('unsupported.song'));

        expect(harness.controller.state.phase, SongImportPhase.failure);
        expect(harness.controller.state.failureCode, 'songImport.unsupported');
        expect(
          await harness.repository.list(const SongQuery()),
          isA<Success>(),
        );
        expect(await harness.workspaceRoot.list().toList(), isEmpty);
      },
    );

    test('passes content-derived part previews into preview state', () async {
      final importer = _ControlledImporter(
        probeResult: const ImportProbeResult.recognized(
          parts: <ImportPartPreview>[
            ImportPartPreview(
              id: 'P1',
              name: 'Guitar',
              staffCount: 1,
              noteCount: 2,
              lowestMidiPitch: 64,
              highestMidiPitch: 67,
              isPolyphonic: true,
              chordSymbolCount: 0,
              hasTablature: true,
            ),
          ],
        ),
      );
      final harness = await _Harness.create(importer: importer);
      addTearDown(harness.dispose);

      harness.controller.requestSelection();
      await harness.controller.selectSource(_source('multipart.song'));

      final preview = harness.controller.state.preview!;
      expect(harness.controller.state.phase, SongImportPhase.preview);
      expect(preview.byteLength, 2);
      expect(preview.parts, hasLength(1));
      expect(preview.parts.single.noteCount, 2);
      expect(preview.parts.single.isPolyphonic, isTrue);
      expect(preview.parts.single.hasTablature, isTrue);
    });
  });
}

final class _Harness {
  _Harness._({
    required this.controller,
    required this.repository,
    required this.workspaceRoot,
  });

  final SongImportController controller;
  final InMemorySongRepository repository;
  final Directory workspaceRoot;

  static Future<_Harness> create({SongImporter? importer}) async {
    final root = await Directory.systemTemp.createTemp(
      'song-import-controller-',
    );
    final repository = InMemorySongRepository(clock: DateTime.now);
    return _Harness._(
      controller: SongImportController(
        registry: ImporterRegistry(
          importers: <SongImporter>[importer ?? _ControlledImporter()],
        ),
        repository: repository,
        workspaceRoot: () async => root,
      ),
      repository: repository,
      workspaceRoot: root,
    );
  }

  Future<void> dispose() async {
    await controller.dispose();
    if (await workspaceRoot.exists()) {
      await workspaceRoot.delete(recursive: true);
    }
  }
}

final class _ControlledImporter implements SongImporter {
  _ControlledImporter({
    this.probeResult = const ImportProbeResult.recognized(),
    this.firstImport,
  });

  final ImportProbeResult probeResult;
  final Completer<AppResult<SongImportResult>>? firstImport;

  @override
  Set<String> get supportedExtensions => const <String>{'.song'};

  @override
  Future<AppResult<SongImportResult>> import(
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken cancellationToken,
  ) =>
      firstImport?.future ??
      Future.value(
        AppResult<SongImportResult>.success(
          SongImportResult(document: _document()),
        ),
      );

  @override
  Future<ImportProbeResult> probe(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  ) => Future.value(probeResult);
}

ImportSourceFile _source(String name) => ImportSourceFile(
  displayName: name,
  byteLength: 2,
  openRead: () => Stream<List<int>>.value(<int>[1, 2]),
);

SongDocument _document() => SongDocument(
  schemaVersion: songDocumentSchemaVersion,
  id: SongId('imported-song'),
  revision: 0,
  metadata: SongMetadata(title: 'Imported song'),
  source: SongSource(
    type: SongSourceType.strumSightJson,
    originalFileName: 'imported.song',
    sha256: 'a' * 64,
    importedAt: DateTime.utc(2026),
    importerVersion: '1.0.0',
  ),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
