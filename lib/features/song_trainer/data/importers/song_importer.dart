import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_document.dart';

/// Platform-independent input supplied by an import picker.
final class ImportSourceFile {
  const ImportSourceFile({
    required this.displayName,
    required this.byteLength,
    required this.openRead,
    this.mimeType,
  });

  final String displayName;
  final int byteLength;
  final Stream<List<int>> Function() openRead;
  final String? mimeType;
}

/// Cooperative cancellation checked between source stream chunks.
abstract interface class CancellationToken {
  bool get isCancelled;
}

/// Default token for callers that have no cancellation handle.
final class NeverCancelledToken implements CancellationToken {
  const NeverCancelledToken();

  @override
  bool get isCancelled => false;
}

/// Options shared by importers in this first, in-memory-only import round.
final class SongImportOptions {
  const SongImportOptions({this.knownSourceHashes = const <String>{}});

  /// Source hashes already present in the library, supplied by the later
  /// application-layer registry. The importer warns but never merges IDs.
  final Set<String> knownSourceHashes;
}

/// Format recognition result. A probe never writes to persistent storage.
final class ImportProbeResult {
  const ImportProbeResult._({
    required this.isRecognized,
    this.warnings = const <String>[],
    this.failureCode,
  });

  const ImportProbeResult.recognized({List<String> warnings = const <String>[]})
    : this._(isRecognized: true, warnings: warnings);

  const ImportProbeResult.failure(String code)
    : this._(isRecognized: false, failureCode: code);

  final bool isRecognized;
  final List<String> warnings;
  final String? failureCode;
}

/// In-memory import output. Persistence and duplicate-library lookup begin in
/// E03-R10, outside this adapter contract.
final class SongImportResult {
  SongImportResult({
    required this.document,
    List<String> warnings = const <String>[],
  }) : warnings = List<String>.unmodifiable(warnings);

  final SongDocument document;
  final List<String> warnings;
}

/// Format adapter contract used by the import application layer.
abstract interface class SongImporter {
  Set<String> get supportedExtensions;

  Future<ImportProbeResult> probe(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  );

  Future<AppResult<SongImportResult>> import(
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken cancellationToken,
  );
}
