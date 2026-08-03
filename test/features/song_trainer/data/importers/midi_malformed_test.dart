import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/song_trainer/data/importers/midi_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/midi_parser_adapter.dart';
import 'package:strumsight/features/song_trainer/data/importers/import_limits.dart';
import 'package:strumsight/features/song_trainer/data/importers/importer_registry.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';

void main() {
  const importer = MidiImporter();

  test('rejects malformed chunks with a stable validation failure', () async {
    final bytes = await File(
      'test/fixtures/song_trainer/midi/malformed_chunks.mid',
    ).readAsBytes();

    final result = await importer.import(
      _source('broken.mid', bytes),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(result.failureOrNull?.code, MidiImportFailureCode.invalidChunk);
  });

  test('stops before parsing a cancelled source', () async {
    final result = await importer.import(
      _source('cancel.mid', const <int>[0x4d, 0x54, 0x68, 0x64]),
      const SongImportOptions(),
      const _CancelledToken(),
    );

    expect(result.failureOrNull, isA<CancelledFailure>());
  });

  test(
    'rejects SMPTE timing and invalid running status without a crash',
    () async {
      final smpte = <int>[
        ...'MThd'.codeUnits,
        0,
        0,
        0,
        6,
        0,
        0,
        0,
        1,
        0xe7,
        0x28,
      ];
      final running = <int>[
        ...'MThd'.codeUnits,
        0,
        0,
        0,
        6,
        0,
        0,
        0,
        1,
        1,
        0xe0,
        ...'MTrk'.codeUnits,
        0,
        0,
        0,
        3,
        0,
        60,
        64,
      ];

      final smpteResult = await importer.import(
        _source('smpte.mid', smpte),
        const SongImportOptions(),
        const NeverCancelledToken(),
      );
      final runningResult = await importer.import(
        _source('running.mid', running),
        const SongImportOptions(),
        const NeverCancelledToken(),
      );

      expect(
        smpteResult.failureOrNull?.code,
        MidiImportFailureCode.smpteUnsupported,
      );
      expect(
        runningResult.failureOrNull?.code,
        MidiParserFailureCode.invalidEvent,
      );
    },
  );

  test('rejects a zero tempo meta event before mapping', () async {
    final zeroTempo = <int>[
      ...'MThd'.codeUnits,
      0,
      0,
      0,
      6,
      0,
      0,
      0,
      1,
      1,
      0xe0,
      ...'MTrk'.codeUnits,
      0,
      0,
      0,
      11,
      0,
      0xff,
      0x51,
      3,
      0,
      0,
      0,
      0,
      0xff,
      0x2f,
      0,
    ];

    final probe = await importer.probe(
      _source('zero-tempo.mid', zeroTempo),
      const NeverCancelledToken(),
    );
    final result = await importer.import(
      _source('zero-tempo.mid', zeroTempo),
      const SongImportOptions(),
      const NeverCancelledToken(),
    );

    expect(probe.failureCode, MidiParserFailureCode.invalidEvent);
    expect(result.failureOrNull?.code, MidiParserFailureCode.invalidEvent);
  });

  test(
    'uses the shared registry event budget without a MIDI-only limit',
    () async {
      final oneNote = await File(
        'test/fixtures/song_trainer/midi/format0.mid',
      ).readAsBytes();
      final twoNotes = await File(
        'test/fixtures/song_trainer/midi/format1_multitrack.mid',
      ).readAsBytes();
      final registry = ImporterRegistry(
        importers: const <SongImporter>[MidiImporter()],
        limits: const ImportLimits(maxEventCount: 1),
      );
      final acceptedSource = _source('one.mid', oneNote);
      final accepted = await registry.import(
        await registry.probe(acceptedSource, const NeverCancelledToken()),
        acceptedSource,
        const SongImportOptions(),
        const NeverCancelledToken(),
      );
      final rejectedSource = _source('two.mid', twoNotes);
      final rejected = await registry.import(
        await registry.probe(rejectedSource, const NeverCancelledToken()),
        rejectedSource,
        const SongImportOptions(),
        const NeverCancelledToken(),
      );

      expect(accepted.valueOrNull, isNotNull);
      expect(
        rejected.failureOrNull?.code,
        ImportLimitFailureCode.eventCountExceeded,
      );
    },
  );
}

final class _CancelledToken implements CancellationToken {
  const _CancelledToken();

  @override
  bool get isCancelled => true;
}

ImportSourceFile _source(String name, List<int> bytes) => ImportSourceFile(
  displayName: name,
  byteLength: bytes.length,
  openRead: () => Stream<List<int>>.value(bytes),
);
