/// Codec for the `index.json` summary sidecar kept next to the song
/// documents (E03-R07, ADR 0090 §Döntés 4, SDD §18.4).
///
/// The codec is the **only** boundary that translates between the on-disk
/// JSON index and the in-memory `[SongSummary]` list the repository
/// exposes. The listview (§27.1) and the recovery scanner both depend on
/// this boundary — a corrupt `index.json` must surface as a stable failure
/// code, never as a `FormatException` or a `TypeError`.
///
/// Wire-incompatible changes bump [SongIndexCodec.schemaVersion]. The
/// current codec refuses to read any document whose `schemaVersion`
/// field is absent, non-integer, negative, or out of range.
library;

import 'dart:convert';

import '../../domain/models/song_id.dart';
import '../../domain/models/song_source.dart';
import '../../domain/repositories/song_repository.dart';

/// Stable exception thrown by [SongIndexCodec.decode] when the input is
/// structurally invalid. Always carries a machine-readable code; never
/// the offending raw value (failure text ends up in logs).
class SongIndexCodecException implements Exception {
  SongIndexCodecException._(this.code, {this.field});

  /// One of [SongIndexCodecErrorCode]'s constants.
  final String code;

  /// Field that failed when the failure is scoped to one; null otherwise.
  final String? field;

  @override
  String toString() =>
      'SongIndexCodecException($code${field == null ? '' : ', field: $field'})';
}

/// Stable machine-readable codes emitted by [SongIndexCodec].
abstract final class SongIndexCodecErrorCode {
  /// Input was not a JSON object.
  static const String rootNotAnObject = 'songIndex.codec.rootNotAnObject';

  /// `schemaVersion` missing or non-integer.
  static const String schemaVersionMissing =
      'songIndex.codec.schemaVersion.missing';

  /// `schemaVersion` is outside `[1, supportedSchemaVersion]`.
  static const String schemaVersionOutOfRange =
      'songIndex.codec.schemaVersion.outOfRange';

  /// `summaries` field missing or wrong type.
  static const String summariesMissing = 'songIndex.codec.summaries.missing';

  /// A `summaries` entry is missing a required field.
  static const String summaryEntryIncomplete =
      'songIndex.codec.summaryEntry.incomplete';

  /// An entry's `documentId` is not a valid [SongId].
  static const String summaryEntryInvalidId =
      'songIndex.codec.summaryEntry.invalidId';

  /// An entry's `documentHash` is not a lower-case 64-char hex string.
  static const String summaryEntryInvalidHash =
      'songIndex.codec.summaryEntry.invalidHash';

  /// An entry's `updatedAt` / `lastPracticedAt` is not an ISO-8601 string.
  static const String summaryEntryInvalidTimestamp =
      'songIndex.codec.summaryEntry.invalidTimestamp';

  /// An entry's `sourceType` does not resolve to a known enum value.
  static const String summaryEntryInvalidSource =
      'songIndex.codec.summaryEntry.invalidSource';

  /// A `[SongSummary]`-shaped entry's `capability` block fails to decode.
  static const String summaryEntryInvalidCapability =
      'songIndex.codec.summaryEntry.invalidCapability';

  /// The same `documentId` appeared more than once — duplicate index
  /// entry is a known recoverable corruption (§6 matrix).
  static const String duplicateEntry = 'songIndex.codec.duplicateEntry';

  /// An entry's `tags` is not a list-of-string.
  static const String summaryEntryInvalidTags =
      'songIndex.codec.summaryEntry.invalidTags';
}

/// The highest wire-incompatible index schema this codec knows how to read.
const int songIndexSupportedSchemaVersion = 1;

/// Default summary-type used when [null] is persisted: an unset
/// capability summary is the canonical "no validator has run since the
/// install" answer. Codec handles this case so the test can pass `null`
/// for the freshly-installed case.
class SongIndexCodec {
  /// Construct a codec. The class is stateless; share one instance.
  const SongIndexCodec();

  /// Encode [summaries] to a UTF-8 JSON byte sequence. The encoding is
  /// deterministic for a given input — see [_summaryToMap].
  List<int> encode(List<SongSummary> summaries) {
    final map = <String, dynamic>{
      'schemaVersion': songIndexSupportedSchemaVersion,
      'summaries': [for (final entry in summaries) _summaryToMap(entry)],
    };
    return utf8.encode(jsonEncode(map));
  }

  /// Decode [bytes] (UTF-8 JSON) to a list of [SongSummary]. Throws a
  /// [SongIndexCodecException] with a stable error code on every
  /// corruption (§6 acceptance "stabile, gépileg olvasható error code").
  List<SongSummary> decode(List<int> bytes) {
    final Object? raw;
    try {
      raw = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw SongIndexCodecException._(SongIndexCodecErrorCode.rootNotAnObject);
    }
    if (raw is! Map<String, dynamic>) {
      throw SongIndexCodecException._(SongIndexCodecErrorCode.rootNotAnObject);
    }
    final schemaVersionRaw = raw['schemaVersion'];
    if (schemaVersionRaw is! int) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.schemaVersionMissing,
        field: 'schemaVersion',
      );
    }
    if (schemaVersionRaw < 1 ||
        schemaVersionRaw > songIndexSupportedSchemaVersion) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.schemaVersionOutOfRange,
        field: 'schemaVersion',
      );
    }
    final summariesRaw = raw['summaries'];
    if (summariesRaw is! List) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summariesMissing,
        field: 'summaries',
      );
    }
    final out = <SongSummary>[];
    final seen = <String>{};
    for (var index = 0; index < summariesRaw.length; index++) {
      final entry = summariesRaw[index];
      if (entry is! Map<String, dynamic>) {
        throw SongIndexCodecException._(
          SongIndexCodecErrorCode.summaryEntryIncomplete,
          field: 'summaries[$index]',
        );
      }
      final summary = _summaryFromMap(entry, index);
      if (!seen.add(summary.documentId.value)) {
        throw SongIndexCodecException._(
          SongIndexCodecErrorCode.duplicateEntry,
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

  static Map<String, dynamic> _summaryToMap(SongSummary entry) {
    return <String, dynamic>{
      'documentId': entry.documentId.value,
      'title': entry.title,
      'artist': entry.artist,
      'tags': List<String>.unmodifiable(entry.tags),
      'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
      'lastPracticedAt': entry.lastPracticedAt.toUtc().toIso8601String(),
      'capability': entry.capability == null
          ? null
          : _capabilityToMap(entry.capability!),
      'sourceType': entry.sourceType.code,
      'favorite': entry.favorite,
      'archived': entry.archived,
      'trashed': entry.trashed,
      'revision': entry.revision,
      'documentHash': entry.documentHash,
    };
  }

  static SongSummary _summaryFromMap(Map<String, dynamic> json, int index) {
    final documentIdRaw = json['documentId'];
    if (documentIdRaw is! String) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summaryEntryInvalidId,
        field: 'summaries[$index].documentId',
      );
    }
    final SongId documentId;
    try {
      documentId = SongId(documentIdRaw);
    } on Object {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summaryEntryInvalidId,
        field: 'summaries[$index].documentId',
      );
    }
    final title = _requireString(json, 'title', index, 'title');
    final artistRaw = json['artist'];
    final artist = artistRaw == null
        ? null
        : artistRaw is String
        ? artistRaw
        : throw SongIndexCodecException._(
            SongIndexCodecErrorCode.summaryEntryIncomplete,
            field: 'summaries[$index].artist',
          );
    final tagsRaw = json['tags'];
    if (tagsRaw is! List) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summaryEntryInvalidTags,
        field: 'summaries[$index].tags',
      );
    }
    final tags = <String>[];
    for (var i = 0; i < tagsRaw.length; i++) {
      final tag = tagsRaw[i];
      if (tag is! String) {
        throw SongIndexCodecException._(
          SongIndexCodecErrorCode.summaryEntryInvalidTags,
          field: 'summaries[$index].tags[$i]',
        );
      }
      tags.add(tag);
    }
    final updatedAt = _requireTimestamp(json, 'updatedAt', index);
    final lastPracticedAt = _requireTimestamp(json, 'lastPracticedAt', index);
    final capabilityRaw = json['capability'];
    final capability = capabilityRaw == null
        ? null
        : capabilityRaw is Map<String, dynamic>
        ? _capabilityFromMap(capabilityRaw, index)
        : throw SongIndexCodecException._(
            SongIndexCodecErrorCode.summaryEntryInvalidCapability,
            field: 'summaries[$index].capability',
          );
    final sourceTypeCode = _requireString(
      json,
      'sourceType',
      index,
      'sourceType',
    );
    final sourceType = songSourceTypeFromCode(sourceTypeCode);
    if (sourceType == null) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summaryEntryInvalidSource,
        field: 'summaries[$index].sourceType',
      );
    }
    final favorite = _requireBool(json, 'favorite', index);
    final archived = _requireBool(json, 'archived', index);
    final trashed = _requireBool(json, 'trashed', index);
    final revision = _requireInt(json, 'revision', index);
    final documentHash = _requireHash(json, 'documentHash', index);

    return SongSummary(
      documentId: documentId,
      title: title,
      artist: artist,
      tags: List<String>.unmodifiable(tags),
      updatedAt: updatedAt,
      lastPracticedAt: lastPracticedAt,
      capability: capability,
      sourceType: sourceType,
      favorite: favorite,
      archived: archived,
      trashed: trashed,
      revision: revision,
      documentHash: documentHash,
    );
  }

  static Map<String, dynamic> _capabilityToMap(SongCapabilitySummary entry) {
    return <String, dynamic>{
      'canPersist': entry.canPersist,
      'canTrain': entry.canTrain,
      'canExport': entry.canExport,
      'chordScoring': entry.chordScoring,
      'pitchScoring': entry.pitchScoring,
      'lastValidatedAt': entry.lastValidatedAt.toUtc().toIso8601String(),
    };
  }

  static SongCapabilitySummary _capabilityFromMap(
    Map<String, dynamic> json,
    int summaryIndex,
  ) {
    return SongCapabilitySummary(
      canPersist: _requireBool(json, 'canPersist', summaryIndex),
      canTrain: _requireBool(json, 'canTrain', summaryIndex),
      canExport: _requireBool(json, 'canExport', summaryIndex),
      chordScoring: _requireBool(json, 'chordScoring', summaryIndex),
      pitchScoring: _requireBool(json, 'pitchScoring', summaryIndex),
      lastValidatedAt: _requireTimestamp(json, 'lastValidatedAt', summaryIndex),
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
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summaryEntryIncomplete,
        field: 'summaries[$index].$prettyField',
      );
    }
    return value;
  }

  static bool _requireBool(Map<String, dynamic> json, String field, int index) {
    final value = json[field];
    if (value is! bool) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summaryEntryIncomplete,
        field: 'summaries[$index].$field',
      );
    }
    return value;
  }

  static int _requireInt(Map<String, dynamic> json, String field, int index) {
    final value = json[field];
    if (value is! int || value < 0) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summaryEntryIncomplete,
        field: 'summaries[$index].$field',
      );
    }
    return value;
  }

  static DateTime _requireTimestamp(
    Map<String, dynamic> json,
    String field,
    int index,
  ) {
    final value = json[field];
    if (value is! String) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summaryEntryInvalidTimestamp,
        field: 'summaries[$index].$field',
      );
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summaryEntryInvalidTimestamp,
        field: 'summaries[$index].$field',
      );
    }
    return parsed.toUtc();
  }

  static String _requireHash(
    Map<String, dynamic> json,
    String field,
    int index,
  ) {
    final value = json[field];
    if (value is! String) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summaryEntryInvalidHash,
        field: 'summaries[$index].$field',
      );
    }
    if (!_isLowerHex64(value)) {
      throw SongIndexCodecException._(
        SongIndexCodecErrorCode.summaryEntryInvalidHash,
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
