import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/data/importers/native_json_exporter.dart';
import 'package:strumsight/features/song_trainer/data/importers/native_json_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';

void main() {
  const importer = NativeJsonImporter();

  group('NativeJsonImporter', () {
    test(
      'recognises a valid native root even with a mismatched extension',
      () async {
        final bytes = await File(
          'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
        ).readAsBytes();

        final probe = await importer.probe(
          _source('shared-song.json', bytes),
          const NeverCancelledToken(),
        );

        expect(probe.isRecognized, isTrue);
        expect(
          probe.warnings,
          contains(NativeJsonImportWarningCode.extensionMismatch),
        );
      },
    );

    test(
      'imports the complete canonical fixture and retains its asset manifest',
      () async {
        final bytes = await File(
          'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
        ).readAsBytes();

        final result = await importer.import(
          _source('full_song.strumsight-song.json', bytes),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );

        expect(result, isA<Success<SongImportResult>>());
        final imported = (result as Success<SongImportResult>).value;
        expect(imported.document.metadata.title, 'Fixture full song');
        expect(imported.document.assets, hasLength(1));
        expect(imported.document.sections, hasLength(1));
        expect(imported.document.tracks, hasLength(1));

        final exported = const NativeJsonExporter().export(imported.document);
        final roundTripped = await importer.import(
          _source(exported.filename, exported.bytes),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );
        expect(roundTripped.valueOrNull?.document, imported.document);
      },
    );

    test(
      'fails closed for malformed JSON and a newer exchange version',
      () async {
        final corrupt = await File(
          'test/fixtures/song_trainer/native/corrupt.strumsight-song.json',
        ).readAsBytes();
        final newer = await File(
          'test/fixtures/song_trainer/native/newer_version.strumsight-song.json',
        ).readAsBytes();
        final invalidRoot = utf8.encode('{"format":"not-strumsight"}');

        final corruptResult = await importer.import(
          _source('corrupt.strumsight-song.json', corrupt),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );
        final newerResult = await importer.import(
          _source('newer.strumsight-song.json', newer),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );
        final invalidRootResult = await importer.import(
          _source('wrong-root.strumsight-song.json', invalidRoot),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );

        expect(
          corruptResult.failureOrNull?.code,
          NativeJsonImportFailureCode.invalidJson,
        );
        expect(
          newerResult.failureOrNull?.code,
          NativeJsonImportFailureCode.unsupportedFormatVersion,
        );
        expect(
          invalidRootResult.failureOrNull?.code,
          NativeJsonImportFailureCode.invalidRoot,
        );
      },
    );

    test(
      'enforces the stream size limit even when declared length lies',
      () async {
        final validBytes = await File(
          'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
        ).readAsBytes();
        final oversizedBytes = List<int>.from(validBytes)
          ..addAll(
            List<int>.filled(
              maxNativeJsonSourceBytes + 1 - validBytes.length,
              0x20,
            ),
          );

        final result = await importer.import(
          _source(
            'song.strumsight-song.json',
            oversizedBytes,
            declaredLength: maxNativeJsonSourceBytes,
          ),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );

        expect(
          result.failureOrNull?.code,
          NativeJsonImportFailureCode.sourceTooLarge,
        );
      },
    );

    test('rejects duplicate entity ids in a native document', () async {
      final bytes = await File(
        'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
      ).readAsBytes();
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final document = root['document'] as Map<String, dynamic>;
      final assets = document['assets'] as List<dynamic>;
      assets.add(
        Map<String, dynamic>.from(assets.single as Map<String, dynamic>),
      );
      root['assetManifest'] = assets;

      final result = await importer.import(
        _source(
          'duplicate.strumsight-song.json',
          utf8.encode(jsonEncode(root)),
        ),
        const SongImportOptions(),
        const NeverCancelledToken(),
      );

      expect(
        result.failureOrNull?.code,
        NativeJsonImportFailureCode.duplicateId,
      );
    });

    test(
      'rejects a manifest-consistent document that would lose an asset',
      () async {
        final bytes = await File(
          'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
        ).readAsBytes();
        final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final document = root['document'] as Map<String, dynamic>;
        (document['assets'] as List<dynamic>).add('not-an-asset');
        (root['assetManifest'] as List<dynamic>).add('not-an-asset');

        final result = await importer.import(
          _source(
            'lossy-asset.strumsight-song.json',
            utf8.encode(jsonEncode(root)),
          ),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );

        expect(
          result.failureOrNull?.code,
          NativeJsonImportFailureCode.invalidDocument,
        );
      },
    );

    test(
      'reports a known source hash without merging document identity',
      () async {
        final bytes = await File(
          'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
        ).readAsBytes();

        final result = await importer.import(
          _source('fixture.strumsight-song.json', bytes),
          SongImportOptions(knownSourceHashes: <String>{'a' * 64}),
          const NeverCancelledToken(),
        );

        expect(
          result.valueOrNull?.warnings,
          contains(NativeJsonImportWarningCode.duplicateSourceHash),
        );
        expect(result.valueOrNull?.document.id.value, 'fixture-song');
      },
    );

    test(
      'turns a malformed nested document value into a stable failure',
      () async {
        final bytes = await File(
          'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
        ).readAsBytes();
        final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final document = root['document'] as Map<String, dynamic>;
        final asset =
            (document['assets'] as List<dynamic>).single
                as Map<String, dynamic>;
        asset['byteLength'] = 'not-a-number';
        final manifestAsset =
            (root['assetManifest'] as List<dynamic>).single
                as Map<String, dynamic>;
        manifestAsset['byteLength'] = 'not-a-number';

        final result = await importer.import(
          _source(
            'malformed.strumsight-song.json',
            utf8.encode(jsonEncode(root)),
          ),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );

        expect(
          result.failureOrNull?.code,
          NativeJsonImportFailureCode.invalidDocument,
        );
      },
    );

    test(
      'rejects a mismatched asset manifest before returning a document',
      () async {
        final bytes = await File(
          'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
        ).readAsBytes();
        final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        raw['assetManifest'] = <Object?>[];

        final result = await importer.import(
          _source('song.strumsight-song.json', utf8.encode(jsonEncode(raw))),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );

        expect(
          result.failureOrNull?.code,
          NativeJsonImportFailureCode.assetManifestMismatch,
        );
      },
    );

    test(
      'accepts sources at and below the 1 MiB limit and rejects max plus one',
      () async {
        final bytes = await File(
          'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
        ).readAsBytes();

        final underLimit = await importer.import(
          _source(
            'song.strumsight-song.json',
            bytes,
            declaredLength: maxNativeJsonSourceBytes - 1,
          ),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );
        final atLimit = await importer.import(
          _source(
            'song.strumsight-song.json',
            bytes,
            declaredLength: maxNativeJsonSourceBytes,
          ),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );
        final overLimit = await importer.import(
          _source(
            'song.strumsight-song.json',
            bytes,
            declaredLength: maxNativeJsonSourceBytes + 1,
          ),
          const SongImportOptions(),
          const NeverCancelledToken(),
        );

        expect(underLimit, isA<Success<SongImportResult>>());
        expect(atLimit, isA<Success<SongImportResult>>());
        expect(
          overLimit.failureOrNull?.code,
          NativeJsonImportFailureCode.sourceTooLarge,
        );
      },
    );

    test(
      'returns cancelled before parsing or committing any import result',
      () async {
        final bytes = await File(
          'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
        ).readAsBytes();

        final result = await importer.import(
          _source('song.strumsight-song.json', bytes),
          const SongImportOptions(),
          const _CancelledToken(),
        );

        expect(result.failureOrNull?.code, 'cancelled');
      },
    );

    test('returns cancelled at a stream safe point before parsing', () async {
      final bytes = await File(
        'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
      ).readAsBytes();

      final result = await importer.import(
        ImportSourceFile(
          displayName: 'song.strumsight-song.json',
          byteLength: bytes.length,
          openRead: () => Stream<List<int>>.fromIterable(<List<int>>[
            bytes.sublist(0, 16),
            bytes.sublist(16),
          ]),
        ),
        const SongImportOptions(),
        _CancelsDuringReadToken(),
      );

      expect(result.failureOrNull?.code, 'cancelled');
    });
  });
}

ImportSourceFile _source(String name, List<int> bytes, {int? declaredLength}) =>
    ImportSourceFile(
      displayName: name,
      byteLength: declaredLength ?? bytes.length,
      openRead: () => Stream<List<int>>.fromIterable(<List<int>>[bytes]),
    );

final class _CancelledToken implements CancellationToken {
  const _CancelledToken();

  @override
  bool get isCancelled => true;
}

final class _CancelsDuringReadToken implements CancellationToken {
  var _checks = 0;

  @override
  bool get isCancelled => ++_checks >= 3;
}
