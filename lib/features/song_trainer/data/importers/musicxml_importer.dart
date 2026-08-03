import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_source.dart';
import 'musicxml_mapper.dart';
import 'musicxml_parser_adapter.dart';
import 'song_importer.dart';

abstract final class MusicXmlImportWarningCode {
  static const String extensionMismatch =
      'songImport.musicXml.extensionMismatch';
  static const String unsupportedElement =
      MusicXmlMapWarningCode.unsupportedElement;
  static const String timingQuantized = MusicXmlMapWarningCode.timingQuantized;
  static const String repeatExpanded = MusicXmlMapWarningCode.repeatExpanded;
  static const String repeatDisplayOnly =
      MusicXmlMapWarningCode.repeatDisplayOnly;
}

abstract final class MusicXmlImportFailureCode {
  static const String sourceRead = 'songImport.musicXml.sourceRead';
  static const String sourceTooLarge = 'songImport.musicXml.sourceTooLarge';
  static const String invalidXml = 'songImport.musicXml.invalidXml';
  static const String doctypeForbidden = 'songImport.musicXml.doctypeForbidden';
  static const String invalidRoot = 'songImport.musicXml.invalidRoot';
}

/// Secure probe and mapper for the documented MusicXML score-partwise subset.
final class MusicXmlImporter implements SongImporter {
  const MusicXmlImporter({
    this.parser = const MusicXmlParserAdapter(),
    this.mapper = const MusicXmlMapper(),
  });

  final MusicXmlParserAdapter parser;
  final MusicXmlMapper mapper;

  @override
  Set<String> get supportedExtensions => const <String>{'.musicxml', '.xml'};

  @override
  Future<ImportProbeResult> probe(
    ImportSourceFile source,
    CancellationToken cancellationToken,
  ) async {
    final read = await readImportSource(source, cancellationToken);
    if (read.cancelled) {
      return const ImportProbeResult.failure(FailureCode.cancelled);
    }
    if (read.failureCode != null) {
      return ImportProbeResult.failure(read.failureCode!);
    }
    final parsed = _parse(read.bytes!);
    if (parsed.failureCode != null) {
      return ImportProbeResult.failure(parsed.failureCode!);
    }
    return ImportProbeResult.recognized(
      warnings: _warnings(source),
      parts: mapper.preview(parsed.document!),
    );
  }

  @override
  Future<AppResult<SongImportResult>> import(
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken cancellationToken,
  ) async {
    final read = await readImportSource(source, cancellationToken);
    if (read.cancelled) {
      return const AppResult<SongImportResult>.failure(CancelledFailure());
    }
    if (read.failureCode != null) return _failure(read.failureCode!);
    final parsed = _parse(read.bytes!);
    if (parsed.failureCode != null) return _failure(parsed.failureCode!);
    if (cancellationToken.isCancelled) {
      return const AppResult<SongImportResult>.failure(CancelledFailure());
    }
    try {
      final mapped = mapper.map(
        xml: parsed.document!,
        displayName: source.displayName,
        originalBytes: read.bytes!,
        sourceType: SongSourceType.musicXml,
      );
      final warnings = <String>[...mapped.warnings, ..._warnings(source)];
      return AppResult<SongImportResult>.success(
        SongImportResult(
          document: mapped.document,
          warnings: warnings,
          parts: mapped.parts,
        ),
      );
    } on FormatException {
      return _failure(MusicXmlImportFailureCode.invalidRoot);
    } on ArgumentError {
      return _failure(MusicXmlImportFailureCode.invalidRoot);
    }
  }

  _ParsedMusicXml _parse(List<int> bytes) {
    final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return const _ParsedMusicXml.failure(
        MusicXmlImportFailureCode.invalidXml,
      );
    }
    if (RegExp(r'<!DOCTYPE', caseSensitive: false).hasMatch(text)) {
      return const _ParsedMusicXml.failure(
        MusicXmlImportFailureCode.doctypeForbidden,
      );
    }
    final document = parser.parse(bytes);
    if (document == null) {
      return const _ParsedMusicXml.failure(
        MusicXmlImportFailureCode.invalidXml,
      );
    }
    if (document.rootElement.name.local != 'score-partwise') {
      return const _ParsedMusicXml.failure(
        MusicXmlImportFailureCode.invalidRoot,
      );
    }
    return _ParsedMusicXml.document(document);
  }

  List<String> _warnings(ImportSourceFile source) =>
      source.displayName.toLowerCase().endsWith('.musicxml') ||
          source.displayName.toLowerCase().endsWith('.xml')
      ? const <String>[]
      : const <String>[MusicXmlImportWarningCode.extensionMismatch];
  AppResult<SongImportResult> _failure(String code) =>
      AppResult<SongImportResult>.failure(ValidationFailure(code: code));
}

final class ImportSourceRead {
  const ImportSourceRead.bytes(this.bytes)
    : failureCode = null,
      cancelled = false;
  const ImportSourceRead.failure(this.failureCode)
    : bytes = null,
      cancelled = false;
  const ImportSourceRead.cancelled()
    : bytes = null,
      failureCode = null,
      cancelled = true;
  final List<int>? bytes;
  final String? failureCode;
  final bool cancelled;
}

Future<ImportSourceRead> readImportSource(
  ImportSourceFile source,
  CancellationToken cancellationToken, {
  int maxBytes = 1_048_576,
}) async {
  if (cancellationToken.isCancelled) return const ImportSourceRead.cancelled();
  if (source.byteLength < 0 || source.byteLength > maxBytes) {
    return const ImportSourceRead.failure(
      MusicXmlImportFailureCode.sourceTooLarge,
    );
  }
  final output = BytesBuilder(copy: false);
  var length = 0;
  try {
    await for (final chunk in source.openRead()) {
      if (cancellationToken.isCancelled) {
        return const ImportSourceRead.cancelled();
      }
      length += chunk.length;
      if (length > maxBytes) {
        return const ImportSourceRead.failure(
          MusicXmlImportFailureCode.sourceTooLarge,
        );
      }
      output.add(chunk);
    }
  } catch (_) {
    return const ImportSourceRead.failure(MusicXmlImportFailureCode.sourceRead);
  }
  return ImportSourceRead.bytes(output.takeBytes());
}

final class _ParsedMusicXml {
  const _ParsedMusicXml.document(this.document) : failureCode = null;
  const _ParsedMusicXml.failure(this.failureCode) : document = null;
  final dynamic document;
  final String? failureCode;
}
