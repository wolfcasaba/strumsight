import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/importers/import_limits.dart';
import 'package:strumsight/features/song_trainer/data/importers/importer_registry.dart';
import 'package:strumsight/features/song_trainer/data/importers/midi_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/musicxml_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/mxl_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/native_json_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';

void main() {
  test(
    'Guitar Pro extensions fail before an importer or source stream is used',
    () async {
      final importer = _CountingImporter();
      final registry = ImporterRegistry(importers: <SongImporter>[importer]);
      final source = _source('practice.GP5');

      await expectLater(
        registry.probe(source.source, const NeverCancelledToken()),
        throwsA(
          isA<ImportRegistryException>().having(
            (error) => error.code,
            'code',
            ImportRegistryFailureCode.guitarProUnsupported,
          ),
        ),
      );

      expect(importer.probeCount, 0);
      expect(source.openReadCount, 0);
    },
  );

  test('a Guitar Pro header fails before an importer is selected', () async {
    final importer = _CountingImporter();
    final registry = ImporterRegistry(importers: <SongImporter>[importer]);
    final source = _source(
      'practice.data',
      bytes: 'FICHIER GUITAR PRO v5.10'.codeUnits,
    );

    await expectLater(
      registry.probe(source.source, const NeverCancelledToken()),
      throwsA(
        isA<ImportRegistryException>().having(
          (error) => error.code,
          'code',
          ImportRegistryFailureCode.guitarProUnsupported,
        ),
      ),
    );

    expect(importer.probeCount, 0);
    expect(source.openReadCount, 1);
  });

  test(
    'a stalled Guitar Pro header check observes the shared wall-time limit',
    () async {
      final importer = _CountingImporter();
      final registry = ImporterRegistry(
        importers: <SongImporter>[importer],
        limits: const ImportLimits(maxWallTime: Duration.zero),
      );
      final source = ImportSourceFile(
        displayName: 'practice.data',
        byteLength: 18,
        openRead: () => Stream<List<int>>.periodic(
          const Duration(days: 1),
          (_) => const <int>[],
        ),
      );

      await expectLater(
        registry.probe(source, const NeverCancelledToken()),
        throwsA(
          isA<ImportRegistryException>().having(
            (error) => error.code,
            'code',
            ImportLimitFailureCode.wallTimeExceeded,
          ),
        ),
      );

      expect(importer.probeCount, 0);
    },
  );

  test(
    'non-Guitar-Pro content keeps the existing generic unsupported result',
    () async {
      final importer = _CountingImporter();
      final registry = ImporterRegistry(importers: <SongImporter>[importer]);

      await expectLater(
        registry.probe(
          _source('practice.data').source,
          const NeverCancelledToken(),
        ),
        throwsA(
          isA<ImportRegistryException>().having(
            (error) => error.code,
            'code',
            ImportRegistryFailureCode.unsupportedContent,
          ),
        ),
      );

      expect(importer.probeCount, 1);
    },
  );

  test(
    'a supported source whose display name contains Guitar Pro reaches an importer',
    () async {
      final importer = _CountingImporter(
        probeResult: const ImportProbeResult.recognized(),
      );
      final registry = ImporterRegistry(importers: <SongImporter>[importer]);

      final selection = await registry.probe(
        _source('guitar pro notes.musicxml').source,
        const NeverCancelledToken(),
      );

      expect(selection.importer, same(importer));
      expect(importer.probeCount, 1);
    },
  );

  test(
    'the production support list remains exactly the four existing importers',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final importers = container.read(songImporterRegistryProvider).importers;

      expect(importers, hasLength(4));
      expect(
        importers.map((importer) => importer.runtimeType),
        unorderedEquals(<Type>[
          NativeJsonImporter,
          MusicXmlImporter,
          MxlImporter,
          MidiImporter,
        ]),
      );
    },
  );
}

final class _CountingImporter implements SongImporter {
  _CountingImporter({
    this.probeResult = const ImportProbeResult.failure(
      ImportRegistryFailureCode.unsupportedContent,
    ),
  });

  var probeCount = 0;
  final ImportProbeResult probeResult;

  @override
  Set<String> get supportedExtensions => const <String>{'.song'};

  @override
  Future<AppResult<SongImportResult>> import(
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken cancellationToken,
  ) => throw UnimplementedError();

  @override
  Future<ImportProbeResult> probe(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  ) async {
    probeCount += 1;
    return probeResult;
  }
}

final class _Source {
  _Source(this.source, this._openReadCount);

  final ImportSourceFile source;
  final int Function() _openReadCount;

  int get openReadCount => _openReadCount();
}

_Source _source(String displayName, {List<int> bytes = const <int>[1, 2]}) {
  var openReadCount = 0;
  return _Source(
    ImportSourceFile(
      displayName: displayName,
      byteLength: bytes.length,
      openRead: () {
        openReadCount += 1;
        return Stream<List<int>>.value(bytes);
      },
    ),
    () => openReadCount,
  );
}
