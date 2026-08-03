import 'dart:async';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_track.dart';
import 'import_limits.dart';
import 'song_importer.dart';

/// Stable failures emitted before an importer is permitted to parse content.
abstract final class ImportRegistryFailureCode {
  static const String unsupportedContent = 'songImport.unsupportedContent';
  static const String guitarProUnsupported = 'songImport.guitarPro.unsupported';
}

const Set<String> _guitarProExtensions = <String>{
  '.gp',
  '.gp3',
  '.gp4',
  '.gp5',
  '.gp6',
  '.gp7',
  '.gp8',
  '.gpx',
};

const List<int> _guitarProHeader = <int>[
  0x46,
  0x49,
  0x43,
  0x48,
  0x49,
  0x45,
  0x52,
  0x20,
  0x47,
  0x55,
  0x49,
  0x54,
  0x41,
  0x52,
  0x20,
  0x50,
  0x52,
  0x4f,
];

/// Selected importer plus the content-derived probe result that chose it.
final class ImporterSelection {
  const ImporterSelection({required this.importer, required this.probe});

  final SongImporter importer;
  final ImportProbeResult probe;
}

/// Content-aware importer chooser shared by the application import flow.
final class ImporterRegistry {
  const ImporterRegistry({
    required this.importers,
    this.limits = const ImportLimits(),
  });

  final List<SongImporter> importers;
  final ImportLimits limits;

  /// Chooses the first importer that recognizes the actual source content.
  Future<ImporterSelection> probe(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  ) async {
    _checkSource(source);
    if (await _isGuitarProSource(source, cancellationToken)) {
      throw const ImportRegistryException(
        ImportRegistryFailureCode.guitarProUnsupported,
      );
    }
    String? failureCode;
    for (final importer in importers) {
      if (cancellationToken.isCancelled) {
        throw const ImportRegistryException(FailureCode.cancelled);
      }
      final result = await importer
          .probe(source, cancellationToken)
          .timeout(limits.maxWallTime);
      if (result.isRecognized) {
        return ImporterSelection(importer: importer, probe: result);
      }
      if (result.failureCode == FailureCode.cancelled) {
        throw const ImportRegistryException(FailureCode.cancelled);
      }
      failureCode ??= result.failureCode;
    }
    throw ImportRegistryException(
      failureCode ?? ImportRegistryFailureCode.unsupportedContent,
    );
  }

  /// Imports through an already content-verified selection under the same limits.
  Future<AppResult<SongImportResult>> import(
    ImporterSelection selection,
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken cancellationToken,
  ) async {
    try {
      _checkSource(source);
      final result = await selection.importer
          .import(source, options, cancellationToken)
          .timeout(limits.maxWallTime);
      if (result case Success<SongImportResult>(:final value)) {
        if (_eventCount(value.document) > limits.maxEventCount) {
          return const AppResult<SongImportResult>.failure(
            ValidationFailure(code: ImportLimitFailureCode.eventCountExceeded),
          );
        }
      }
      return result;
    } on TimeoutException {
      return const AppResult<SongImportResult>.failure(
        ValidationFailure(code: ImportLimitFailureCode.wallTimeExceeded),
      );
    } on ImportRegistryException catch (error) {
      return AppResult<SongImportResult>.failure(
        error.code == FailureCode.cancelled
            ? const CancelledFailure()
            : ValidationFailure(code: error.code),
      );
    }
  }

  void _checkSource(ImportSourceFile source) {
    if (source.byteLength < 0 || source.byteLength > limits.maxSourceBytes) {
      throw const ImportRegistryException(
        ImportLimitFailureCode.sourceBytesExceeded,
      );
    }
  }

  Future<bool> _isGuitarProSource(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  ) async {
    final displayName = source.displayName.toLowerCase();
    if (_guitarProExtensions.any(displayName.endsWith)) {
      return true;
    }
    if (cancellationToken.isCancelled) {
      throw const ImportRegistryException(FailureCode.cancelled);
    }
    if (source.byteLength < _guitarProHeader.length) return false;

    StreamIterator<List<int>>? stream;
    try {
      stream = StreamIterator<List<int>>(source.openRead());
      var index = 0;
      final matchesHeader = () async {
        while (await stream!.moveNext()) {
          final chunk = stream.current;
          if (cancellationToken.isCancelled) {
            throw const ImportRegistryException(FailureCode.cancelled);
          }
          for (final byte in chunk) {
            if (byte != _guitarProHeader[index]) return false;
            index += 1;
            if (index == _guitarProHeader.length) return true;
          }
        }
        return false;
      }();
      return await matchesHeader.timeout(
        limits.maxWallTime,
        onTimeout: () => throw const ImportRegistryException(
          ImportLimitFailureCode.wallTimeExceeded,
        ),
      );
    } on ImportRegistryException {
      rethrow;
    } catch (_) {
      // The existing importers retain ownership of generic source-read errors.
      return false;
    } finally {
      await stream?.cancel();
    }
  }

  int _eventCount(SongDocument document) => document.tracks.fold<int>(
    0,
    (count, track) =>
        count +
        switch (track) {
          ChordTrack(:final events) => events.length,
          StrumTrack(:final events) => events.length,
          NoteTrack(:final events) => events.length,
          LyricsTrack(:final events) => events.length,
          MarkerTrack(:final events) => events.length,
          BackingAudioTrack() => 0,
        },
  );
}

final class ImportRegistryException implements Exception {
  const ImportRegistryException(this.code);

  final String code;
}
