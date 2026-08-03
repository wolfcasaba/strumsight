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
    this.parts = const <ImportPartPreview>[],
    this.failureCode,
  });

  const ImportProbeResult.recognized({
    List<String> warnings = const <String>[],
    List<ImportPartPreview> parts = const <ImportPartPreview>[],
  }) : this._(isRecognized: true, warnings: warnings, parts: parts);

  const ImportProbeResult.failure(String code)
    : this._(isRecognized: false, failureCode: code);

  final bool isRecognized;
  final List<String> warnings;
  final List<ImportPartPreview> parts;
  final String? failureCode;
}

/// Content-derived summary of a selectable source part, safe for previews.
final class ImportPartPreview {
  const ImportPartPreview({
    required this.id,
    required this.name,
    required this.staffCount,
    required this.noteCount,
    required this.isPolyphonic,
    required this.chordSymbolCount,
    required this.hasTablature,
    this.midiProgram,
    this.lowestMidiPitch,
    this.highestMidiPitch,
    this.channel,
    this.duration,
    this.suspectedDrum,
    this.isMonophonic,
  });

  final String id;
  final String name;
  final int? midiProgram;
  final int staffCount;
  final int noteCount;
  final int? lowestMidiPitch;
  final int? highestMidiPitch;
  final int? channel;
  final Duration? duration;
  final bool? suspectedDrum;
  final bool? isMonophonic;
  final bool isPolyphonic;
  final int chordSymbolCount;
  final bool hasTablature;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportPartPreview &&
          other.id == id &&
          other.name == name &&
          other.midiProgram == midiProgram &&
          other.staffCount == staffCount &&
          other.noteCount == noteCount &&
          other.lowestMidiPitch == lowestMidiPitch &&
          other.highestMidiPitch == highestMidiPitch &&
          other.channel == channel &&
          other.duration == duration &&
          other.suspectedDrum == suspectedDrum &&
          other.isMonophonic == isMonophonic &&
          other.isPolyphonic == isPolyphonic &&
          other.chordSymbolCount == chordSymbolCount &&
          other.hasTablature == hasTablature;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    midiProgram,
    staffCount,
    noteCount,
    lowestMidiPitch,
    highestMidiPitch,
    channel,
    duration,
    suspectedDrum,
    isMonophonic,
    isPolyphonic,
    chordSymbolCount,
    hasTablature,
  );
}

/// In-memory import output. Persistence and duplicate-library lookup begin in
/// E03-R10, outside this adapter contract.
final class SongImportResult {
  SongImportResult({
    required this.document,
    List<String> warnings = const <String>[],
    List<ImportPartPreview> parts = const <ImportPartPreview>[],
  }) : warnings = List<String>.unmodifiable(warnings),
       parts = List<ImportPartPreview>.unmodifiable(parts);

  final SongDocument document;
  final List<String> warnings;
  final List<ImportPartPreview> parts;
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
