/// File-backed summary-index codec and store for the audio-analysis
/// repository (ADR 0239 §Döntés 4 + §Döntés 5, E06-R21 brief §5.4 / §6).
///
/// The index sidecar lives at `<root>/index.json` and stores a list of
/// [AnalysisSummary] entries. The index is **rebuildable**: missing
/// or corrupt index triggers a full rebuild from the `documents/`
/// directory (the brief §6 "index-újraépítés" cell covers both the
/// missing and the corrupt case).
///
/// The codec is deliberately distinct from [AnalysisDocumentCodec]
/// (E06-R03, ADR 0221): the index does NOT carry the document body
/// and does NOT depend on any V2 enum tree beyond the `completionStatus`
/// string.
library;

import 'dart:convert';
import 'dart:io';

import '../../domain/analysis_summary.dart';

/// The codec's `schemaVersion` field — bump when changing the wire
/// shape in a wire-incompatible way (ADR 0239 §Visszavonás feltétele).
const int analysisIndexSchemaVersion = 1;

/// Stable exception thrown when the on-disk index cannot be decoded.
/// Always carries a machine-readable code so a future migration tool
/// can act without parsing strings.
class AnalysisIndexCodecException implements Exception {
  AnalysisIndexCodecException._(this.code, {this.field});

  final String code;
  final String? field;

  @override
  String toString() =>
      'AnalysisIndexCodecException($code${field == null ? '' : ', field: $field'})';
}

/// Stable error codes emitted by [AnalysisIndexCodec].
abstract final class AnalysisIndexCodecErrorCode {
  static const String rootNotAnObject = 'analysis.index.codec.rootNotAnObject';
  static const String schemaVersionMissing =
      'analysis.index.codec.schemaVersion.missing';
  static const String schemaVersionOutOfRange =
      'analysis.index.codec.schemaVersion.outOfRange';
  static const String summariesMissing =
      'analysis.index.codec.summaries.missing';
  static const String summaryEntryIncomplete =
      'analysis.index.codec.summaryEntry.incomplete';
  static const String summaryEntryInvalidTimestamp =
      'analysis.index.codec.summaryEntry.invalidTimestamp';
  static const String summaryEntryInvalidHash =
      'analysis.index.codec.summaryEntry.invalidHash';
  static const String duplicateEntry = 'analysis.index.codec.duplicateEntry';
}

/// Deterministic UTF-8 JSON codec for the analysis summary index.
final class AnalysisIndexCodec {
  const AnalysisIndexCodec();

  /// Encode [summaries] to a UTF-8 byte sequence. The output is
  /// deterministic for a given input.
  List<int> encode(List<AnalysisSummary> summaries) {
    final map = <String, Object?>{
      'schemaVersion': analysisIndexSchemaVersion,
      'summaries': <Map<String, Object?>>[
        for (final summary in summaries) _toMap(summary),
      ],
    };
    return utf8.encode(jsonEncode(map));
  }

  /// Decode [bytes] (UTF-8 JSON) into a list of [AnalysisSummary].
  /// Throws [AnalysisIndexCodecException] with a stable code on every
  /// corruption — the repository treats this as "rebuild required".
  List<AnalysisSummary> decode(List<int> bytes) {
    final Object? raw;
    try {
      raw = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.rootNotAnObject,
      );
    }
    if (raw is! Map<String, dynamic>) {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.rootNotAnObject,
      );
    }
    final schemaVersionRaw = raw['schemaVersion'];
    if (schemaVersionRaw is! int) {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.schemaVersionMissing,
        field: 'schemaVersion',
      );
    }
    if (schemaVersionRaw < 1 || schemaVersionRaw > analysisIndexSchemaVersion) {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.schemaVersionOutOfRange,
        field: 'schemaVersion',
      );
    }
    final summariesRaw = raw['summaries'];
    if (summariesRaw is! List) {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.summariesMissing,
        field: 'summaries',
      );
    }
    final out = <AnalysisSummary>[];
    final seen = <String>{};
    for (var index = 0; index < summariesRaw.length; index++) {
      final entry = summariesRaw[index];
      if (entry is! Map<String, dynamic>) {
        throw AnalysisIndexCodecException._(
          AnalysisIndexCodecErrorCode.summaryEntryIncomplete,
          field: 'summaries[$index]',
        );
      }
      final summary = _fromMap(entry, index);
      if (!seen.add(summary.documentId)) {
        throw AnalysisIndexCodecException._(
          AnalysisIndexCodecErrorCode.duplicateEntry,
          field: 'summaries[$index].documentId',
        );
      }
      out.add(summary);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Per-entry codec
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _toMap(AnalysisSummary summary) =>
      <String, Object?>{
        'documentId': summary.documentId,
        'title': summary.title,
        'customTitle': summary.customTitle,
        'createdAt': summary.createdAt.toUtc().toIso8601String(),
        'completionStatus': summary.completionStatus,
        'documentHash': summary.documentHash,
        'sizeBytes': summary.sizeBytes,
      };

  static AnalysisSummary _fromMap(Map<String, dynamic> json, int index) {
    final documentId = _requireString(json, 'documentId', index, 'documentId');
    final title = _requireString(json, 'title', index, 'title');
    final customTitle = _requireBool(json, 'customTitle', index);
    final createdAtRaw = json['createdAt'];
    if (createdAtRaw is! String) {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.summaryEntryInvalidTimestamp,
        field: 'summaries[$index].createdAt',
      );
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.summaryEntryInvalidTimestamp,
        field: 'summaries[$index].createdAt',
      );
    }
    final completionStatus = _requireString(
      json,
      'completionStatus',
      index,
      'completionStatus',
    );
    final documentHash = _requireHash(json, 'documentHash', index);
    final sizeBytes = _requireInt(json, 'sizeBytes', index);
    return AnalysisSummary(
      documentId: documentId,
      title: title,
      customTitle: customTitle,
      createdAt: createdAt.toUtc(),
      completionStatus: completionStatus,
      documentHash: documentHash,
      sizeBytes: sizeBytes,
    );
  }

  // ---------------------------------------------------------------------------
  // Low-level helpers
  // ---------------------------------------------------------------------------

  static String _requireString(
    Map<String, dynamic> json,
    String field,
    int index,
    String prettyField,
  ) {
    final value = json[field];
    if (value is! String) {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.summaryEntryIncomplete,
        field: 'summaries[$index].$prettyField',
      );
    }
    return value;
  }

  static bool _requireBool(Map<String, dynamic> json, String field, int index) {
    final value = json[field];
    if (value is! bool) {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.summaryEntryIncomplete,
        field: 'summaries[$index].$field',
      );
    }
    return value;
  }

  static int _requireInt(Map<String, dynamic> json, String field, int index) {
    final value = json[field];
    if (value is! int || value < 0) {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.summaryEntryIncomplete,
        field: 'summaries[$index].$field',
      );
    }
    return value;
  }

  static String _requireHash(
    Map<String, dynamic> json,
    String field,
    int index,
  ) {
    final value = json[field];
    if (value is! String) {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.summaryEntryInvalidHash,
        field: 'summaries[$index].$field',
      );
    }
    if (!_isLowerHex64(value)) {
      throw AnalysisIndexCodecException._(
        AnalysisIndexCodecErrorCode.summaryEntryInvalidHash,
        field: 'summaries[$index].$field',
      );
    }
    return value;
  }

  static bool _isLowerHex64(String value) {
    if (value.length != 64) return false;
    for (var i = 0; i < value.length; i++) {
      final rune = value.codeUnitAt(i);
      final isDigit = rune >= 0x30 && rune <= 0x39;
      final isLowerHex = rune >= 0x61 && rune <= 0x66;
      if (!isDigit && !isLowerHex) return false;
    }
    return true;
  }
}

/// File-backed analysis summary index, rebuilt on corruption
/// (ADR 0239 §Döntés 4 + §Döntés 5).
///
/// The store is **framework-independent** — no Flutter, Riverpod,
/// SharedPreferences, or `path_provider` import. The production
/// provider (`application/analysis_providers.dart`) is responsible
/// for resolving the platform directory and passing it via the
/// constructor.
final class AnalysisIndexStore {
  AnalysisIndexStore._({required this.file, required this.codec});

  /// File backing the index (`<root>/index.json`).
  final File file;

  /// Codec used to (de)serialise the index.
  final AnalysisIndexCodec codec;

  /// Open an index store against an existing directory; the file is
  /// not created eagerly. The directory is assumed to already exist.
  factory AnalysisIndexStore.openAtDirectory({
    required Directory directory,
    String indexFileName = 'index.json',
    AnalysisIndexCodec codec = const AnalysisIndexCodec(),
  }) {
    return AnalysisIndexStore._(
      file: File('${directory.path}/$indexFileName'),
      codec: codec,
    );
  }

  /// Read every summary currently in the index. Returns an empty list
  /// when the file is absent.
  List<AnalysisSummary> read() {
    if (!file.existsSync()) return <AnalysisSummary>[];
    final bytes = file.readAsBytesSync();
    return codec.decode(bytes);
  }

  /// Persist [summaries] atomically by writing to a sibling `.tmp-*`
  /// file and renaming on top of [file].
  void write(List<AnalysisSummary> summaries) {
    final bytes = codec.encode(summaries);
    final staging = File('${file.path}.tmp-1');
    staging.writeAsBytesSync(bytes, flush: true);
    try {
      staging.renameSync(file.path);
    } on FileSystemException {
      if (file.existsSync()) {
        file.deleteSync(recursive: false);
      }
      staging.renameSync(file.path);
    }
    if (staging.existsSync()) {
      try {
        staging.deleteSync(recursive: false);
      } on FileSystemException {
        // Best-effort cleanup; the recovery scanner covers the gap.
      }
    }
  }

  /// Remove the index file from disk (used when the repository evicts
  /// the last document, or as the first step of a manual recovery).
  void remove() {
    if (file.existsSync()) {
      try {
        file.deleteSync(recursive: false);
      } on FileSystemException {
        // Best-effort — recovery will rebuild.
      }
    }
  }
}
