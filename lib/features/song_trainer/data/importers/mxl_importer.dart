import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_source.dart';
import 'import_limits.dart';
import 'musicxml_importer.dart';
import 'musicxml_mapper.dart';
import 'musicxml_parser_adapter.dart';
import 'mxl_archive_reader.dart';
import 'song_importer.dart';

/// MXL is a bounded ZIP container whose root MusicXML is mapped in memory.
final class MxlImporter implements SongImporter {
  const MxlImporter({
    this.limits = const ImportLimits(),
    this.reader = const MxlArchiveReader(),
    this.parser = const MusicXmlParserAdapter(),
    this.mapper = const MusicXmlMapper(),
  });
  final ImportLimits limits;
  final MxlArchiveReader reader;
  final MusicXmlParserAdapter parser;
  final MusicXmlMapper mapper;

  @override
  Set<String> get supportedExtensions => const <String>{'.mxl'};

  @override
  Future<ImportProbeResult> probe(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  ) async {
    final result = await import(
      source,
      const SongImportOptions(),
      cancellationToken,
    );
    return result.isSuccess
        ? const ImportProbeResult.recognized()
        : ImportProbeResult.failure(result.failureOrNull!.code);
  }

  @override
  Future<AppResult<SongImportResult>> import(
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken cancellationToken,
  ) async {
    final input = await readImportSource(
      source,
      cancellationToken,
      maxBytes: limits.maxSourceBytes,
    );
    if (input.cancelled) {
      return const AppResult<SongImportResult>.failure(CancelledFailure());
    }
    if (input.failureCode != null) {
      return AppResult<SongImportResult>.failure(
        ValidationFailure(code: input.failureCode!),
      );
    }
    final extracted = reader.read(input.bytes!, limits);
    if (extracted.failureCode != null) {
      return AppResult<SongImportResult>.failure(
        ValidationFailure(code: extracted.failureCode!),
      );
    }
    final parsed = parser.parse(extracted.scoreBytes!);
    if (parsed == null || parsed.rootElement.name.local != 'score-partwise') {
      return const AppResult<SongImportResult>.failure(
        ValidationFailure(code: MusicXmlImportFailureCode.invalidXml),
      );
    }
    try {
      return AppResult<SongImportResult>.success(
        mapper.map(
          xml: parsed,
          displayName: source.displayName,
          originalBytes: input.bytes!,
          sourceType: SongSourceType.compressedMusicXml,
        ),
      );
    } on FormatException {
      return const AppResult<SongImportResult>.failure(
        ValidationFailure(code: MusicXmlImportFailureCode.invalidXml),
      );
    }
  }
}
