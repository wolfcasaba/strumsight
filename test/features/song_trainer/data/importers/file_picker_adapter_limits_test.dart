// Regression: the picker adapter must enforce ImportLimits.maxSourceBytes at
// the data boundary, BEFORE buffering the picked payload into memory. Before
// this guard `fromXFile` drained the whole stream (and copied it a second time
// through `List.unmodifiable`) and only the registry rejected it afterwards —
// an oversize pick therefore allocated the full file first.
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';
import 'package:strumsight/features/song_trainer/data/importers/import_limits.dart';
import 'package:strumsight/features/song_trainer/data/importers/importer_registry.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';

/// Fails the test if the adapter opens the stream at all: an oversize pick has
/// to be rejected from the reported length alone.
final class _UnreadableXFile extends XFile {
  _UnreadableXFile(this.reportedLength) : super('oversize.musicxml');

  final int reportedLength;

  @override
  Future<int> length() async => reportedLength;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) =>
      throw StateError('openRead must not run for an oversize pick');
}

/// `length()` under-reports (a stream-backed pick can do this); the payload is
/// the authority, so the running total has to abort the read.
final class _UnderReportingXFile extends XFile {
  _UnderReportingXFile(this.chunkCount, this.chunkSize)
    : super('lying.musicxml');

  final int chunkCount;
  final int chunkSize;
  int emittedChunks = 0;

  @override
  Future<int> length() async => chunkSize;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    for (var i = 0; i < chunkCount; i++) {
      emittedChunks += 1;
      yield Uint8List(chunkSize);
    }
  }
}

Future<String?> registryFailureCode(
  ImportSourceFile source, {
  ImportLimits limits = const ImportLimits(),
}) async {
  try {
    await ImporterRegistry(
      importers: const <SongImporter>[],
      limits: limits,
    ).probe(source, const NeverCancelledToken());
    return null;
  } on ImportRegistryException catch (error) {
    return error.code;
  }
}

void main() {
  const limits = ImportLimits();

  test('rejects an oversize pick without reading a single byte', () async {
    final file = _UnreadableXFile(limits.maxSourceBytes + 1);

    final source = await PlatformFilePickerAdapter.fromXFile(file);

    expect(source.byteLength, greaterThan(limits.maxSourceBytes));
    expect(
      await registryFailureCode(source),
      ImportLimitFailureCode.sourceBytesExceeded,
    );
  });

  test(
    'aborts the read when the stream outgrows the reported length',
    () async {
      const chunkSize = 64 * 1024;
      final chunkCount = (limits.maxSourceBytes ~/ chunkSize) + 4;
      final file = _UnderReportingXFile(chunkCount, chunkSize);

      final source = await PlatformFilePickerAdapter.fromXFile(file);

      expect(source.byteLength, greaterThan(limits.maxSourceBytes));
      expect(file.emittedChunks, lessThan(chunkCount));
      expect(
        await registryFailureCode(source),
        ImportLimitFailureCode.sourceBytesExceeded,
      );
    },
  );

  // Regression (round-2): a rejected pick must refuse to read with the SAME
  // typed failure `ImporterRegistry._checkSource` raises, never with an empty
  // stream. The song editor's backing attach reaches `openRead()` directly
  // (the import flow is rejected earlier, on `byteLength`), so silence there
  // was a user-visible no-op: no attach, no message, no log.
  test('a rejected pick refuses to read with the registry failure', () async {
    final source = await PlatformFilePickerAdapter.fromXFile(
      _UnreadableXFile(limits.maxSourceBytes + 1),
    );

    await expectLater(
      source.openRead(),
      emitsError(
        isA<ImportRegistryException>().having(
          (error) => error.code,
          'code',
          ImportLimitFailureCode.sourceBytesExceeded,
        ),
      ),
    );
    // Every reopen refuses the same way, not just the first.
    await expectLater(
      source.openRead(),
      emitsError(isA<ImportRegistryException>()),
    );
  });

  test('a stream that outgrows its length refuses the same way', () async {
    const chunkSize = 64 * 1024;
    final source = await PlatformFilePickerAdapter.fromXFile(
      _UnderReportingXFile((limits.maxSourceBytes ~/ chunkSize) + 4, chunkSize),
    );

    await expectLater(
      source.openRead(),
      emitsError(
        isA<ImportRegistryException>().having(
          (error) => error.code,
          'code',
          ImportLimitFailureCode.sourceBytesExceeded,
        ),
      ),
    );
  });

  // Regression: `byteLength` is measured, never fabricated. For a lying stream
  // it is what the stream had already delivered when the guard tripped — a
  // real lower bound above the cap, so the shared limit check still rejects it.
  test('an aborted read reports the bytes it actually saw', () async {
    const chunkSize = 64 * 1024;
    final chunkCount = (limits.maxSourceBytes ~/ chunkSize) + 4;
    final file = _UnderReportingXFile(chunkCount, chunkSize);

    final source = await PlatformFilePickerAdapter.fromXFile(file);

    expect(source.byteLength, file.emittedChunks * chunkSize);
    expect(source.byteLength, greaterThan(limits.maxSourceBytes));
    expect(source.byteLength, lessThan(chunkCount * chunkSize));
  });

  // Regression: an oversize pick reported with its real length is rejected by
  // `ImporterRegistry` on `byteLength` alone, so the import path never reaches
  // the refusing stream and keeps its existing failure message.
  test('an oversize pick reports the length the platform gave', () async {
    final source = await PlatformFilePickerAdapter.fromXFile(
      _UnreadableXFile(limits.maxSourceBytes + 4096),
    );

    expect(source.byteLength, limits.maxSourceBytes + 4096);
  });

  // Regression: the limit is a parameter, not a constant baked into the
  // adapter, so a registry configured with a non-default `ImportLimits` and the
  // picker in front of it enforce one and the same budget.
  test('enforces the injected limit rather than the default', () async {
    const tight = ImportLimits(maxSourceBytes: 1024);
    final source = await PlatformFilePickerAdapter.fromXFile(
      XFile.fromData(Uint8List(4096), path: 'tight.musicxml'),
      limits: tight,
    );

    expect(source.byteLength, greaterThan(tight.maxSourceBytes));
    expect(
      await registryFailureCode(source, limits: tight),
      ImportLimitFailureCode.sourceBytesExceeded,
    );
    expect(const PlatformFilePickerAdapter(limits: tight).limits, same(tight));
  });

  test('a pick at the limit is still buffered and reopenable', () async {
    final payload = Uint8List(limits.maxSourceBytes)
      ..[0] = 7
      ..[limits.maxSourceBytes - 1] = 9;

    final source = await PlatformFilePickerAdapter.fromXFile(
      XFile.fromData(payload, path: 'atlimit.musicxml'),
    );

    expect(source.byteLength, limits.maxSourceBytes);
    expect(
      await registryFailureCode(source),
      isNot(ImportLimitFailureCode.sourceBytesExceeded),
    );
    expect(
      await source.openRead().expand((chunk) => chunk).length,
      limits.maxSourceBytes,
    );
    expect(
      await source.openRead().expand((chunk) => chunk).length,
      limits.maxSourceBytes,
    );
  });

  // Regression: `BytesBuilder(copy: false)` hands back the very buffer the
  // picker stream emitted, and the same instance is replayed by every
  // `openRead()`. It leaves the boundary as an unmodifiable view, so a
  // consumer write throws instead of silently corrupting a later reopen.
  test('the buffered payload stays unmodifiable across reopens', () async {
    final payload = Uint8List(64)..[0] = 7;

    final source = await PlatformFilePickerAdapter.fromXFile(
      XFile.fromData(payload, path: 'immutable.musicxml'),
    );

    final chunk = await source.openRead().first;
    expect(chunk[0], 7);
    expect(() => chunk[0] = 9, throwsUnsupportedError);
    expect((await source.openRead().first)[0], 7);
  });
}
