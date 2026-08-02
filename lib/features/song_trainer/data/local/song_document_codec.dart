import 'dart:convert';

import '../../../../core/music/tuning.dart';
import '../../domain/models/song_asset_reference.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_marker.dart';
import '../../domain/models/song_metadata.dart';
import '../../domain/models/song_source.dart';

/// Stable codec failure on a malformed or unrecognised [SongDocument] JSON
/// blob. Always carries a machine-readable [code]; never the offending value
/// (records are user content — failure text ends up in logs).
class SongDocumentCodecException implements Exception {
  SongDocumentCodecException._(this.code, {this.field});

  /// One of [SongDocumentCodecErrorCode]'s constants.
  final String code;

  /// The field that failed when the failure is scoped to one.
  final String? field;

  @override
  String toString() =>
      'SongDocumentCodecException($code${field == null ? '' : ', field: $field'})';
}

/// Stable machine-readable codes emitted by the document codec.
abstract final class SongDocumentCodecErrorCode {
  static const String notAnObject = 'songDocument.codec.notAnObject';
  static const String schemaVersionMissing =
      'songDocument.codec.schemaVersion.missing';
  static const String schemaVersionOutOfRange =
      'songDocument.codec.schemaVersion.outOfRange';
  static const String schemaVersionUnknown =
      'songDocument.codec.schemaVersion.unknown';
  static const String revisionOutOfRange =
      'songDocument.codec.revision.outOfRange';
  static const String idMissing = 'songDocument.codec.id.missing';
  static const String metadataMissing = 'songDocument.codec.metadata.missing';
  static const String sourceMissing = 'songDocument.codec.source.missing';
  static const String createdAtMissing = 'songDocument.codec.createdAt.missing';
  static const String createdAtInvalid = 'songDocument.codec.createdAt.invalid';
  static const String updatedAtMissing = 'songDocument.codec.updatedAt.missing';
  static const String updatedAtInvalid = 'songDocument.codec.updatedAt.invalid';
  static const String sourceTypeUnknown =
      'songDocument.codec.source.type.unknown';
  static const String assetsNotAList = 'songDocument.codec.assets.notAList';
  static const String markersNotAList = 'songDocument.codec.markers.notAList';
}

/// Maximum number of asset references a single encoded document may carry.
/// Mirrors [SongDocument]'s constructor bound so an inflated record is
/// rejected at the codec boundary.
const int _codecMaxAssetCount = 64;

/// Maximum number of markers a single encoded document may carry.
const int _codecMaxMarkerCount = 1024;

/// Platform-independent, deterministic JSON codec for [SongDocument].
///
/// The codec is the single boundary between the in-memory domain model and
/// any persisted representation. Two design rules are enforced here:
///
/// 1. **Byte-identical determinism.** Two consecutive encodes of the same
///    document produce the same bytes — the canonical key order is fixed
///    in [_documentToMap], and every sub-object follows the same pattern.
///    The reviewer can rely on this for hash-based dedup tests.
/// 2. **UTC timestamp policy.** Dates are persisted as UTC ISO-8601 strings
///    (§5 kötött döntések 2); decoded values are flagged as UTC, and a
///    future-versioned schema that wants a different policy must bump
///    [supportedSchemaVersion] and gate here.
class SongDocumentCodec {
  /// Creates a codec. The constructor is parameterless today — the only
  /// configuration knob ([supportedSchemaVersion]) is a `static const` so a
  /// future test override is a single-line change.
  const SongDocumentCodec();

  /// The highest schema version this codec knows how to read. A future
  /// bump rejects older / newer documents at decode time.
  static const int supportedSchemaVersion = 1;

  /// Encode [document] to a UTF-8 JSON byte sequence. The encoding is
  /// deterministic for a given input — see class doc.
  List<int> encode(SongDocument document) {
    final map = _documentToMap(document);
    return utf8.encode(jsonEncode(map));
  }

  /// Decode [bytes] (UTF-8 JSON) to a [SongDocument]. Throws a
  /// [SongDocumentCodecException] with a stable error code on any
  /// validation failure (no silent fallbacks).
  SongDocument decode(List<int> bytes) {
    final Object? raw;
    try {
      raw = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.notAnObject,
      );
    }
    if (raw is! Map<String, dynamic>) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.notAnObject,
      );
    }
    return _documentFromMap(raw);
  }

  // ---------------------------------------------------------------------------
  // Document envelope
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _documentToMap(SongDocument document) {
    return <String, dynamic>{
      'schemaVersion': document.schemaVersion,
      'id': document.id.value,
      'revision': document.revision,
      'metadata': _metadataToMap(document.metadata),
      'source': _sourceToMap(document.source),
      'assets': <Map<String, dynamic>>[
        for (final asset in document.assets) _assetToMap(asset),
      ],
      'markers': <Map<String, dynamic>>[
        for (final marker in document.markers) _markerToMap(marker),
      ],
      'createdAt': document.createdAt.toUtc().toIso8601String(),
      'updatedAt': document.updatedAt.toUtc().toIso8601String(),
    };
  }

  static SongDocument _documentFromMap(Map<String, dynamic> json) {
    final schemaVersion = _requireIntInRange(
      json,
      'schemaVersion',
      SongDocumentCodecErrorCode.schemaVersionMissing,
      SongDocumentCodecErrorCode.schemaVersionOutOfRange,
      min: songDocumentSchemaVersion,
      max: supportedSchemaVersion,
    );
    if (schemaVersion > supportedSchemaVersion) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.schemaVersionUnknown,
        field: 'schemaVersion',
      );
    }
    final idValue = _requireString(
      json,
      'id',
      SongDocumentCodecErrorCode.idMissing,
    );
    // stored as flat string above; nested-map form kept for forward-compat.
    final revision = _requireIntInRange(
      json,
      'revision',
      SongDocumentCodecErrorCode.revisionOutOfRange,
      SongDocumentCodecErrorCode.revisionOutOfRange,
      min: 0,
    );
    final metadataRaw = json['metadata'];
    if (metadataRaw is! Map<String, dynamic>) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.metadataMissing,
        field: 'metadata',
      );
    }
    final sourceRaw = json['source'];
    if (sourceRaw is! Map<String, dynamic>) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.sourceMissing,
        field: 'source',
      );
    }
    final createdAtRaw = _requireString(
      json,
      'createdAt',
      SongDocumentCodecErrorCode.createdAtMissing,
    );
    final updatedAtRaw = _requireString(
      json,
      'updatedAt',
      SongDocumentCodecErrorCode.updatedAtMissing,
    );
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.createdAtInvalid,
        field: 'createdAt',
      );
    }
    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (updatedAt == null) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.updatedAtInvalid,
        field: 'updatedAt',
      );
    }

    final assetsRaw = json['assets'];
    final List<SongAssetReference> assets;
    if (assetsRaw is List) {
      if (assetsRaw.length > _codecMaxAssetCount) {
        throw SongDocumentCodecException._(
          SongDocumentCodecErrorCode.assetsNotAList,
          field: 'assets',
        );
      }
      assets = <SongAssetReference>[
        for (final entry in assetsRaw)
          if (entry is Map<String, dynamic>) _assetFromMap(entry),
      ];
    } else if (assetsRaw == null) {
      assets = const <SongAssetReference>[];
    } else {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.assetsNotAList,
        field: 'assets',
      );
    }

    final markersRaw = json['markers'];
    final List<SongMarker> markers;
    if (markersRaw is List) {
      if (markersRaw.length > _codecMaxMarkerCount) {
        throw SongDocumentCodecException._(
          SongDocumentCodecErrorCode.markersNotAList,
          field: 'markers',
        );
      }
      markers = <SongMarker>[
        for (final entry in markersRaw)
          if (entry is Map<String, dynamic>) _markerFromMap(entry),
      ];
    } else if (markersRaw == null) {
      markers = const <SongMarker>[];
    } else {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.markersNotAList,
        field: 'markers',
      );
    }

    return SongDocument(
      schemaVersion: schemaVersion,
      id: SongId(idValue),
      revision: revision,
      metadata: _metadataFromMap(metadataRaw),
      source: _sourceFromMap(sourceRaw),
      assets: assets,
      markers: markers,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }

  // ---------------------------------------------------------------------------
  // SongId
  // ---------------------------------------------------------------------------
  // Metadata
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _metadataToMap(SongMetadata metadata) {
    return <String, dynamic>{
      'title': metadata.title,
      if (metadata.artist != null) 'artist': metadata.artist,
      if (metadata.album != null) 'album': metadata.album,
      if (metadata.composer != null) 'composer': metadata.composer,
      if (metadata.copyright != null) 'copyright': metadata.copyright,
      'tags': <String>[...metadata.tags],
      if (metadata.notes != null) 'notes': metadata.notes,
      if (metadata.defaultTuning != null)
        'defaultTuningId': metadata.defaultTuning!.id,
      'defaultCapo': metadata.defaultCapo,
      if (metadata.originalKey != null) 'originalKey': metadata.originalKey,
      if (metadata.artworkAssetId != null)
        'artworkAssetId': metadata.artworkAssetId!.value,
    };
  }

  static SongMetadata _metadataFromMap(Map<String, dynamic> json) {
    final tuningId = json['defaultTuningId'];
    return SongMetadata(
      title: _requireString(
        Map<String, dynamic>.from(json),
        'title',
        SongDocumentCodecErrorCode.metadataMissing,
      ),
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      composer: json['composer'] as String?,
      copyright: json['copyright'] as String?,
      tags: <String>[
        for (final entry in (json['tags'] as List?) ?? const <Object?>[])
          if (entry is String) entry,
      ],
      notes: json['notes'] as String?,
      defaultTuning: tuningId is String ? Tunings.byId(tuningId) : null,
      defaultCapo: (json['defaultCapo'] as num?)?.toInt() ?? 0,
      originalKey: json['originalKey'] as String?,
      artworkAssetId: json['artworkAssetId'] is String
          ? SongAssetId(json['artworkAssetId'] as String)
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Source
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _sourceToMap(SongSource source) {
    return <String, dynamic>{
      'type': source.type.code,
      'originalFileName': source.originalFileName,
      'sha256': source.sha256,
      'importedAt': source.importedAt.toUtc().toIso8601String(),
      'importerVersion': source.importerVersion,
      if (source.formatVersion != null) 'formatVersion': source.formatVersion,
      'warningSummary': <String>[...source.warningSummary],
      if (source.originalAssetId != null)
        'originalAssetId': source.originalAssetId!.value,
    };
  }

  static SongSource _sourceFromMap(Map<String, dynamic> json) {
    final typeCode = _requireString(
      json,
      'type',
      SongDocumentCodecErrorCode.sourceTypeUnknown,
    );
    final type = songSourceTypeFromCode(typeCode);
    if (type == null) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.sourceTypeUnknown,
        field: 'type',
      );
    }
    final importedAtRaw = _requireString(
      json,
      'importedAt',
      SongDocumentCodecErrorCode.createdAtInvalid,
    );
    final importedAt = DateTime.tryParse(importedAtRaw);
    if (importedAt == null) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.createdAtInvalid,
        field: 'importedAt',
      );
    }
    return SongSource(
      type: type,
      originalFileName: _requireString(
        json,
        'originalFileName',
        SongDocumentCodecErrorCode.sourceMissing,
      ),
      sha256: _requireString(
        json,
        'sha256',
        SongDocumentCodecErrorCode.sourceMissing,
      ),
      importedAt: importedAt.toUtc(),
      importerVersion: _requireString(
        json,
        'importerVersion',
        SongDocumentCodecErrorCode.sourceMissing,
      ),
      formatVersion: json['formatVersion'] as String?,
      warningSummary: <String>[
        for (final entry
            in (json['warningSummary'] as List?) ?? const <Object?>[])
          if (entry is String) entry,
      ],
      originalAssetId: json['originalAssetId'] is String
          ? SongAssetId(json['originalAssetId'] as String)
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Asset reference
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _assetToMap(SongAssetReference asset) {
    return <String, dynamic>{
      'id': asset.id.value,
      'sha256': asset.sha256,
      'extension': asset.extension,
      'byteLength': asset.byteLength,
      if (asset.mimeType != null) 'mimeType': asset.mimeType,
      if (asset.durationMs != null) 'durationMs': asset.durationMs,
    };
  }

  static SongAssetReference _assetFromMap(Map<String, dynamic> json) {
    return SongAssetReference(
      id: SongAssetId(
        _requireString(json, 'id', SongDocumentCodecErrorCode.idMissing),
      ),
      sha256: _requireString(
        json,
        'sha256',
        SongDocumentCodecErrorCode.sourceMissing,
      ),
      extension: _requireString(
        json,
        'extension',
        SongDocumentCodecErrorCode.sourceMissing,
      ),
      byteLength: (json['byteLength'] as num).toInt(),
      mimeType: json['mimeType'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt(),
    );
  }

  // ---------------------------------------------------------------------------
  // Marker
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _markerToMap(SongMarker marker) {
    return <String, dynamic>{
      'id': marker.id.value,
      'label': marker.label,
      'measureIndex': marker.measureIndex,
      'kind': marker.kind,
      if (marker.notes != null) 'notes': marker.notes,
    };
  }

  static SongMarker _markerFromMap(Map<String, dynamic> json) {
    return SongMarker(
      SongMarkerId(
        _requireString(json, 'id', SongDocumentCodecErrorCode.idMissing),
      ),
      _requireString(json, 'label', SongDocumentCodecErrorCode.sourceMissing),
      (json['measureIndex'] as num).toInt(),
      _requireString(json, 'kind', SongDocumentCodecErrorCode.sourceMissing),
      notes: json['notes'] as String?,
    );
  }

  // ---------------------------------------------------------------------------
  // Low-level helpers
  // ---------------------------------------------------------------------------

  static String _requireString(
    Map<String, dynamic> json,
    String field,
    String missingCode,
  ) {
    final value = json[field];
    if (value is! String) {
      throw SongDocumentCodecException._(missingCode, field: field);
    }
    return value;
  }

  static int _requireIntInRange(
    Map<String, dynamic> json,
    String field,
    String missingCode,
    String outOfRangeCode, {
    required int min,
    int? max,
  }) {
    final value = json[field];
    if (value is! num) {
      throw SongDocumentCodecException._(missingCode, field: field);
    }
    final asInt = value.toInt();
    if (asInt < min || (max != null && asInt > max)) {
      throw SongDocumentCodecException._(outOfRangeCode, field: field);
    }
    return asInt;
  }
}
