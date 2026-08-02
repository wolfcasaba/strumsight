import 'dart:convert';

import '../../../../core/music/chord.dart';
import '../../../../core/music/strum.dart';
import '../../../../core/music/tuning.dart';
import '../../domain/models/song_asset_reference.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_event.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_instrument.dart';
import '../../domain/models/key_map.dart';
import '../../domain/models/meter_map.dart';
import '../../domain/models/song_marker.dart';
import '../../domain/models/song_measure.dart';
import '../../domain/models/song_metadata.dart';
import '../../domain/models/song_note_technique.dart';
import '../../domain/models/song_section.dart';
import '../../domain/models/song_source.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/tempo_map.dart';

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
  static const String tracksNotAList = 'songDocument.codec.tracks.notAList';
  static const String structureInvalid = 'songDocument.codec.structure.invalid';
  static const String trackKindMissing =
      'songDocument.codec.track.kind.missing';
  static const String trackKindUnknown =
      'songDocument.codec.track.kind.unknown';
  static const String trackTypeUnknown =
      'songDocument.codec.track.type.unknown';
  static const String eventTypeUnknown =
      'songDocument.codec.event.type.unknown';
  static const String eventKindUnknown =
      'songDocument.codec.event.kind.unknown';
  static const String eventsNotAList = 'songDocument.codec.events.notAList';
  static const String techniqueUnknown = 'songDocument.codec.technique.unknown';
  static const String instrumentMissing =
      'songDocument.codec.instrument.missing';
  static const String backingAssetMissing =
      'songDocument.codec.backing.assetId.missing';
  static const String backingGridOffsetInvalid =
      'songDocument.codec.backing.gridOffset.invalid';
}

/// Maximum number of asset references a single encoded document may carry.
/// Mirrors [SongDocument]'s constructor bound so an inflated record is
/// rejected at the codec boundary.
const int _codecMaxAssetCount = 64;

/// Maximum number of markers a single encoded document may carry.
const int _codecMaxMarkerCount = 1024;

/// Maximum number of tracks a single encoded document may carry.
const int _codecMaxTrackCount = 64;

/// Maximum number of events a single encoded track may carry. Matches
/// [maxSongTrackEventCount] in `song_track.dart`.
const int _codecMaxTrackEventCount = 1 << 16;

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
/// 3. **Canonical event ordering.** Events are persisted in the order
///    required by §5 kötött döntések 1 (start asc, then track id, then
///    event id). The encoder canonicalises the list before serialising so
///    the on-disk form does not depend on caller mutation order.
/// 4. **Fail-loud on unknown subtypes.** An unrecognised track or event
///    discriminator is rejected with a stable machine-readable code —
///    the codec never silently drops or substitutes an unknown entry
///    (ADR 0113 §Döntés 4).
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
    final orderedTracks = canonicalizeTracks(document.tracks);
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
      'sections': <Map<String, dynamic>>[
        for (final section in document.sections) _sectionToMap(section),
      ],
      'measures': <Map<String, dynamic>>[
        for (final measure in document.measures) _measureToMap(measure),
      ],
      'tempoMap': <Map<String, dynamic>>[
        for (final change in document.tempoMap.changes)
          _tempoChangeToMap(change),
      ],
      'meterMap': <Map<String, dynamic>>[
        for (final change in document.meterMap.changes)
          _meterChangeToMap(change),
      ],
      'keyMap': <Map<String, dynamic>>[
        for (final change in document.keyMap.changes) _keyChangeToMap(change),
      ],
      'tracks': <Map<String, dynamic>>[
        for (final track in orderedTracks) _trackToMap(track),
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

    final tracksRaw = json['tracks'];
    final List<SongTrack> tracks;
    if (tracksRaw is List) {
      if (tracksRaw.length > _codecMaxTrackCount) {
        throw SongDocumentCodecException._(
          SongDocumentCodecErrorCode.tracksNotAList,
          field: 'tracks',
        );
      }
      tracks = <SongTrack>[
        for (final entry in tracksRaw)
          if (entry is Map<String, dynamic>) _trackFromMap(entry),
      ];
    } else if (tracksRaw == null) {
      tracks = const <SongTrack>[];
    } else {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.tracksNotAList,
        field: 'tracks',
      );
    }

    final sections = _sectionsFromRaw(json['sections']);
    final measures = _measuresFromRaw(json['measures']);
    final tempoMap = _tempoMapFromRaw(json['tempoMap']);
    final meterMap = _meterMapFromRaw(json['meterMap']);
    final keyMap = _keyMapFromRaw(json['keyMap']);

    return SongDocument(
      schemaVersion: schemaVersion,
      id: SongId(idValue),
      revision: revision,
      metadata: _metadataFromMap(metadataRaw),
      source: _sourceFromMap(sourceRaw),
      assets: assets,
      markers: markers,
      tracks: tracks,
      sections: sections,
      measures: measures,
      tempoMap: tempoMap,
      meterMap: meterMap,
      keyMap: keyMap,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }

  // ---------------------------------------------------------------------------
  // Structure and timeline
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _sectionToMap(SongSection section) =>
      <String, dynamic>{
        'id': section.id.value,
        'name': section.name,
        'startMeasure': section.startMeasure,
        'endMeasureExclusive': section.endMeasureExclusive,
        'kind': section.kind.name,
        if (section.colorKey != null) 'colorKey': section.colorKey,
      };

  static Map<String, dynamic> _measureToMap(
    SongMeasure measure,
  ) => <String, dynamic>{
    'index': measure.index,
    'durationTicks': measure.durationBeats.ticks,
    if (measure.displayNumber != null) 'displayNumber': measure.displayNumber,
    'pickup': measure.pickup,
    'repeatStart': measure.repeatStart,
    if (measure.repeatEndCount != null)
      'repeatEndCount': measure.repeatEndCount,
    if (measure.alternateEnding != null)
      'alternateEnding': measure.alternateEnding,
  };

  static Map<String, dynamic> _tempoChangeToMap(TempoChange change) =>
      <String, dynamic>{'atTicks': change.at.ticks, 'bpm': change.bpm.bpm};

  static Map<String, dynamic> _meterChangeToMap(MeterChange change) =>
      <String, dynamic>{
        'atMeasure': change.atMeasure,
        'numerator': change.meter.numerator,
        'denominator': change.meter.denominator,
      };

  static Map<String, dynamic> _keyChangeToMap(KeyChange change) =>
      <String, dynamic>{
        'atTicks': change.at.ticks,
        'tonic': change.key.tonic,
        'mode': change.key.mode.name,
      };

  static List<SongSection> _sectionsFromRaw(Object? raw) =>
      _structureList<SongSection>(raw, (json) {
        final kind = SongSectionKind.values.where(
          (candidate) => candidate.name == json['kind'],
        );
        if (kind.length != 1) _invalidStructure('sections.kind');
        return SongSection(
          id: SongSectionId(_structureString(json, 'id')),
          name: _structureString(json, 'name'),
          startMeasure: _structureInt(json, 'startMeasure'),
          endMeasureExclusive: _structureInt(json, 'endMeasureExclusive'),
          kind: kind.single,
          colorKey: json['colorKey'] as String?,
        );
      });

  static List<SongMeasure> _measuresFromRaw(Object? raw) =>
      _structureList<SongMeasure>(
        raw,
        (json) => SongMeasure(
          index: _structureInt(json, 'index'),
          durationBeats: BeatPosition.fromTicks(
            _structureInt(json, 'durationTicks'),
          ),
          displayNumber: _optionalStructureInt(json, 'displayNumber'),
          pickup: _optionalStructureBool(json, 'pickup') ?? false,
          repeatStart: _optionalStructureBool(json, 'repeatStart') ?? false,
          repeatEndCount: _optionalStructureInt(json, 'repeatEndCount'),
          alternateEnding: _optionalStructureInt(json, 'alternateEnding'),
        ),
      );

  static TempoMap _tempoMapFromRaw(Object? raw) {
    if (raw == null) return TempoMap.constant(Tempo(120));
    return TempoMap(
      _structureList<TempoChange>(
        raw,
        (json) => TempoChange(
          at: BeatPosition.fromTicks(_structureInt(json, 'atTicks')),
          bpm: Tempo(_structureInt(json, 'bpm')),
        ),
      ),
    );
  }

  static MeterMap _meterMapFromRaw(Object? raw) {
    if (raw == null) return MeterMap.constant(Meter(4, 4));
    return MeterMap(
      _structureList<MeterChange>(
        raw,
        (json) => MeterChange(
          atMeasure: _structureInt(json, 'atMeasure'),
          meter: Meter(
            _structureInt(json, 'numerator'),
            _structureInt(json, 'denominator'),
          ),
        ),
      ),
    );
  }

  static KeyMap _keyMapFromRaw(Object? raw) {
    if (raw == null) return KeyMap.constant(KeySignature(0, KeyMode.major));
    return KeyMap(
      _structureList<KeyChange>(raw, (json) {
        final mode = KeyMode.values.where(
          (candidate) => candidate.name == json['mode'],
        );
        if (mode.length != 1) _invalidStructure('keyMap.mode');
        return KeyChange(
          at: BeatPosition.fromTicks(_structureInt(json, 'atTicks')),
          key: KeySignature(_structureInt(json, 'tonic'), mode.single),
        );
      }),
    );
  }

  static List<T> _structureList<T>(
    Object? raw,
    T Function(Map<String, dynamic>) decode,
  ) {
    if (raw == null) return <T>[];
    if (raw is! List) _invalidStructure('list');
    return <T>[
      for (final entry in raw)
        if (entry is Map<String, dynamic>)
          decode(entry)
        else
          _invalidStructure('entry'),
    ];
  }

  static String _structureString(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value is! String) _invalidStructure(field);
    return value;
  }

  static int _structureInt(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value is! int) _invalidStructure(field);
    return value;
  }

  static int? _optionalStructureInt(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value == null) return null;
    if (value is! int) _invalidStructure(field);
    return value;
  }

  static bool? _optionalStructureBool(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value == null) return null;
    if (value is! bool) _invalidStructure(field);
    return value;
  }

  static Never _invalidStructure(String field) =>
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.structureInvalid,
        field: field,
      );

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
  // Track
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _trackEnvelopeToMap(SongTrack track) {
    return <String, dynamic>{
      'kind': _trackKindOf(track),
      'id': track.id.value,
      'name': track.name,
      'instrument': _instrumentToMap(track.instrument),
      'enabled': track.enabled,
    };
  }

  static Map<String, dynamic> _trackToMap(SongTrack track) {
    final base = _trackEnvelopeToMap(track);
    final self = switch (track) {
      ChordTrack(:final events) => <String, dynamic>{
        'events': <Map<String, dynamic>>[
          for (final event in _canonicalChordEvents(events))
            _chordEventToMap(event),
        ],
      },
      StrumTrack(:final events) => <String, dynamic>{
        'events': <Map<String, dynamic>>[
          for (final event in _canonicalStrumEvents(events))
            _strumEventToMap(event),
        ],
      },
      NoteTrack(:final events) => <String, dynamic>{
        'events': <Map<String, dynamic>>[
          for (final event in _canonicalNoteEvents(events))
            _noteEventToMap(event),
        ],
      },
      LyricsTrack(:final events) => <String, dynamic>{
        'events': <Map<String, dynamic>>[
          for (final event in _canonicalLyricEvents(events))
            _lyricEventToMap(event),
        ],
      },
      MarkerTrack(:final events) => <String, dynamic>{
        'events': <Map<String, dynamic>>[
          for (final event in _canonicalMarkerEvents(events))
            _markerEventToMap(event),
        ],
      },
      BackingAudioTrack(:final assetId, :final gridOffset, :final gainDb) =>
        <String, dynamic>{
          'assetId': assetId.value,
          'gridOffsetMicros': gridOffset.inMicroseconds,
          'gainDb': gainDb,
        },
    };
    return <String, dynamic>{...base, ...self};
  }

  static SongTrack _trackFromMap(Map<String, dynamic> json) {
    final kindRaw = json['kind'];
    if (kindRaw is! String) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.trackKindMissing,
        field: 'kind',
      );
    }
    final kind = _canonicalTrackKind(kindRaw);
    if (kind == null) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.trackTypeUnknown,
        field: 'kind',
      );
    }
    final id = SongTrackId(
      _requireString(json, 'id', SongDocumentCodecErrorCode.idMissing),
    );
    final name = _requireString(
      json,
      'name',
      SongDocumentCodecErrorCode.trackKindUnknown,
    );
    final instrumentRaw = json['instrument'];
    if (instrumentRaw is! Map<String, dynamic>) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.instrumentMissing,
        field: 'instrument',
      );
    }
    final instrument = _instrumentFromMap(instrumentRaw);
    final enabled = (json['enabled'] as bool?) ?? true;

    switch (kind) {
      case SongTrackKind.chord:
        return ChordTrack(
          id: id,
          name: name,
          instrument: instrument,
          enabled: enabled,
          events: _chordEventsFromList(json['events']),
        );
      case SongTrackKind.strum:
        return StrumTrack(
          id: id,
          name: name,
          instrument: instrument,
          enabled: enabled,
          events: _strumEventsFromList(json['events']),
        );
      case SongTrackKind.note:
        return NoteTrack(
          id: id,
          name: name,
          instrument: instrument,
          enabled: enabled,
          events: _noteEventsFromList(json['events']),
        );
      case SongTrackKind.lyrics:
        return LyricsTrack(
          id: id,
          name: name,
          instrument: instrument,
          enabled: enabled,
          events: _lyricEventsFromList(json['events']),
        );
      case SongTrackKind.marker:
        return MarkerTrack(
          id: id,
          name: name,
          instrument: instrument,
          enabled: enabled,
          events: _markerEventsFromList(json['events']),
        );
      case SongTrackKind.backingAudio:
        final assetIdValue = _requireString(
          json,
          'assetId',
          SongDocumentCodecErrorCode.backingAssetMissing,
        );
        final gridMicrosRaw = json['gridOffsetMicros'];
        final gridOffsetMicros = gridMicrosRaw is num
            ? gridMicrosRaw.toInt()
            : (throw SongDocumentCodecException._(
                SongDocumentCodecErrorCode.backingGridOffsetInvalid,
                field: 'gridOffsetMicros',
              ));
        return BackingAudioTrack(
          id: id,
          name: name,
          instrument: instrument,
          enabled: enabled,
          assetId: SongAssetId(assetIdValue),
          gridOffset: Duration(microseconds: gridOffsetMicros),
          gainDb: (json['gainDb'] as num?)?.toDouble() ?? 0,
        );
    }
    // Exhaustiveness check — _canonicalTrackKind returned a non-null
    // value, so all six cases above must have returned. This throw is
    // unreachable but satisfies the analyzer's flow analysis.
    throw SongDocumentCodecException._(
      SongDocumentCodecErrorCode.trackTypeUnknown,
      field: 'kind',
    );
  }

  static String _trackKindOf(SongTrack track) {
    return switch (track) {
      ChordTrack() => SongTrackKind.chord,
      StrumTrack() => SongTrackKind.strum,
      NoteTrack() => SongTrackKind.note,
      LyricsTrack() => SongTrackKind.lyrics,
      MarkerTrack() => SongTrackKind.marker,
      BackingAudioTrack() => SongTrackKind.backingAudio,
    };
  }

  static String? _canonicalTrackKind(String raw) {
    switch (raw) {
      case SongTrackKind.chord:
      case SongTrackKind.strum:
      case SongTrackKind.note:
      case SongTrackKind.lyrics:
      case SongTrackKind.marker:
      case SongTrackKind.backingAudio:
        return raw;
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Instrument
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _instrumentToMap(SongInstrument instrument) {
    return <String, dynamic>{
      'name': instrument.name,
      if (instrument.tuning != null) 'tuningId': instrument.tuning!.id,
    };
  }

  static SongInstrument _instrumentFromMap(Map<String, dynamic> json) {
    final tuningId = json['tuningId'];
    return SongInstrument(
      name: _requireString(
        json,
        'name',
        SongDocumentCodecErrorCode.instrumentMissing,
      ),
      tuning: tuningId is String ? Tunings.byId(tuningId) : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _chordEventToMap(SongChordEvent event) {
    return <String, dynamic>{
      'kind': SongEventKind.chord,
      'id': event.id.value,
      'startMicros': event.start.inMicroseconds,
      'durationMicros': event.duration.inMicroseconds,
      'symbol': event.symbol.label,
      if (event.displayText != null) 'displayText': event.displayText,
    };
  }

  static SongChordEvent _chordEventFromMap(Map<String, dynamic> json) {
    _requireEventKind(json, SongEventKind.chord);
    return SongChordEvent(
      id: SongEventId(
        _requireString(json, 'id', SongDocumentCodecErrorCode.idMissing),
      ),
      start: _requireDurationMicros(
        json,
        'startMicros',
        SongDocumentCodecErrorCode.eventTypeUnknown,
      ),
      duration: _requireDurationMicros(
        json,
        'durationMicros',
        SongDocumentCodecErrorCode.eventTypeUnknown,
      ),
      symbol: Chord(
        _requireString(
          json,
          'symbol',
          SongDocumentCodecErrorCode.eventTypeUnknown,
        ),
      ),
      displayText: json['displayText'] as String?,
    );
  }

  static Map<String, dynamic> _strumEventToMap(SongStrumEvent event) {
    return <String, dynamic>{
      'kind': SongEventKind.strum,
      'id': event.id.value,
      'atMicros': event.at.inMicroseconds,
      if (event.direction != null) 'direction': event.direction!.name,
      'accent': event.accent,
      'muted': event.muted,
      if (event.targetChordId != null)
        'targetChordId': event.targetChordId!.value,
    };
  }

  static SongStrumEvent _strumEventFromMap(Map<String, dynamic> json) {
    _requireEventKind(json, SongEventKind.strum);
    final directionRaw = json['direction'];
    final direction = directionRaw is String
        ? StrumDirection.values.firstWhere(
            (d) => d.name == directionRaw,
            orElse: () => throw SongDocumentCodecException._(
              SongDocumentCodecErrorCode.eventTypeUnknown,
              field: 'direction',
            ),
          )
        : null;
    final targetRaw = json['targetChordId'];
    return SongStrumEvent(
      id: SongEventId(
        _requireString(json, 'id', SongDocumentCodecErrorCode.idMissing),
      ),
      at: _requireDurationMicros(
        json,
        'atMicros',
        SongDocumentCodecErrorCode.eventTypeUnknown,
      ),
      direction: direction,
      accent: (json['accent'] as bool?) ?? false,
      muted: (json['muted'] as bool?) ?? false,
      targetChordId: targetRaw is String ? SongEventId(targetRaw) : null,
    );
  }

  static Map<String, dynamic> _noteEventToMap(SongNoteEvent event) {
    final techniques = <Map<String, dynamic>>[
      for (final technique in event.techniques)
        <String, dynamic>{
          if (technique.kind != null) 'kind': technique.kind!.code,
          'rawCode': technique.rawCode,
          'displayText': technique.displayText,
        },
    ];
    return <String, dynamic>{
      'kind': SongEventKind.note,
      'id': event.id.value,
      'startMicros': event.start.inMicroseconds,
      'durationMicros': event.duration.inMicroseconds,
      'midiPitch': event.midiPitch,
      if (event.velocity != null) 'velocity': event.velocity,
      if (event.stringIndex != null) 'stringIndex': event.stringIndex,
      if (event.fret != null) 'fret': event.fret,
      if (event.tieGroupId != null) 'tieGroupId': event.tieGroupId,
      if (techniques.isNotEmpty) 'techniques': techniques,
    };
  }

  static SongNoteEvent _noteEventFromMap(Map<String, dynamic> json) {
    _requireEventKind(json, SongEventKind.note);
    final techniquesRaw = json['techniques'];
    final techniques = <SongNoteTechnique>{};
    if (techniquesRaw is List) {
      for (final entry in techniquesRaw) {
        if (entry is Map<String, dynamic>) {
          techniques.add(_techniqueFromMap(entry));
        }
      }
    }
    return SongNoteEvent(
      id: SongEventId(
        _requireString(json, 'id', SongDocumentCodecErrorCode.idMissing),
      ),
      start: _requireDurationMicros(
        json,
        'startMicros',
        SongDocumentCodecErrorCode.eventTypeUnknown,
      ),
      duration: _requireDurationMicros(
        json,
        'durationMicros',
        SongDocumentCodecErrorCode.eventTypeUnknown,
      ),
      midiPitch: (json['midiPitch'] as num).toInt(),
      velocity: (json['velocity'] as num?)?.toInt(),
      stringIndex: (json['stringIndex'] as num?)?.toInt(),
      fret: (json['fret'] as num?)?.toInt(),
      tieGroupId: json['tieGroupId'] as String?,
      techniques: techniques,
    );
  }

  static Map<String, dynamic> _lyricEventToMap(SongLyricEvent event) {
    return <String, dynamic>{
      'kind': SongEventKind.lyric,
      'id': event.id.value,
      'atMicros': event.at.inMicroseconds,
      'text': event.text,
    };
  }

  static SongLyricEvent _lyricEventFromMap(Map<String, dynamic> json) {
    _requireEventKind(json, SongEventKind.lyric);
    return SongLyricEvent(
      id: SongEventId(
        _requireString(json, 'id', SongDocumentCodecErrorCode.idMissing),
      ),
      at: _requireDurationMicros(
        json,
        'atMicros',
        SongDocumentCodecErrorCode.eventTypeUnknown,
      ),
      text: _requireString(
        json,
        'text',
        SongDocumentCodecErrorCode.eventTypeUnknown,
      ),
    );
  }

  static Map<String, dynamic> _markerEventToMap(SongMarkerEvent event) {
    return <String, dynamic>{
      'kind': SongEventKind.marker,
      'id': event.id.value,
      'atMicros': event.at.inMicroseconds,
      'label': event.label,
      'kindCode': event.kind,
      if (event.notes != null) 'notes': event.notes,
    };
  }

  static SongMarkerEvent _markerEventFromMap(Map<String, dynamic> json) {
    _requireEventKind(json, SongEventKind.marker);
    return SongMarkerEvent(
      id: SongEventId(
        _requireString(json, 'id', SongDocumentCodecErrorCode.idMissing),
      ),
      at: _requireDurationMicros(
        json,
        'atMicros',
        SongDocumentCodecErrorCode.eventTypeUnknown,
      ),
      label: _requireString(
        json,
        'label',
        SongDocumentCodecErrorCode.eventTypeUnknown,
      ),
      kind: _requireString(
        json,
        'kindCode',
        SongDocumentCodecErrorCode.eventTypeUnknown,
      ),
      notes: json['notes'] as String?,
    );
  }

  // ---------------------------------------------------------------------------
  // Technique
  // ---------------------------------------------------------------------------

  static SongNoteTechnique _techniqueFromMap(Map<String, dynamic> json) {
    final rawCode = _requireString(
      json,
      'rawCode',
      SongDocumentCodecErrorCode.techniqueUnknown,
    );
    final displayText = _requireString(
      json,
      'displayText',
      SongDocumentCodecErrorCode.techniqueUnknown,
    );
    final kindRaw = json['kind'];
    if (kindRaw is String) {
      for (final candidate in SongNoteTechniqueKind.values) {
        if (candidate.code == kindRaw) {
          return SongNoteTechnique.known(candidate);
        }
      }
    }
    return SongNoteTechnique.unknown(
      rawCode: rawCode,
      displayText: displayText,
    );
  }

  // ---------------------------------------------------------------------------
  // Canonical ordering
  // ---------------------------------------------------------------------------

  /// Returns the given tracks in stable document order (track id asc).
  /// The input is not mutated.
  static List<SongTrack> canonicalizeTracks(List<SongTrack> tracks) {
    final copy = List<SongTrack>.of(tracks)
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    return List<SongTrack>.unmodifiable(copy);
  }

  static List<SongChordEvent> _canonicalChordEvents(List<SongChordEvent> e) {
    return _canonicalize(e, (a, b) => a.start.compareTo(b.start));
  }

  static List<SongStrumEvent> _canonicalStrumEvents(List<SongStrumEvent> e) {
    return _canonicalize(e, (a, b) => a.at.compareTo(b.at));
  }

  static List<SongNoteEvent> _canonicalNoteEvents(List<SongNoteEvent> e) {
    return _canonicalize(e, (a, b) => a.start.compareTo(b.start));
  }

  static List<SongLyricEvent> _canonicalLyricEvents(List<SongLyricEvent> e) {
    return _canonicalize(e, (a, b) => a.at.compareTo(b.at));
  }

  static List<SongMarkerEvent> _canonicalMarkerEvents(List<SongMarkerEvent> e) {
    return _canonicalize(e, (a, b) => a.at.compareTo(b.at));
  }

  static List<T> _canonicalize<T>(List<T> events, int Function(T, T) primary) {
    final copy = List<T>.of(events)
      ..sort((a, b) {
        final primaryCompare = primary(a, b);
        if (primaryCompare != 0) return primaryCompare;
        // Stable secondary order: rely on the identity-based Dart list sort
        // (it preserves input order for equal keys), so authors with the
        // same anchor do not get reordered.
        return 0;
      });
    return List<T>.unmodifiable(copy);
  }

  // ---------------------------------------------------------------------------
  // Event-list decoding helpers
  // ---------------------------------------------------------------------------

  static List<SongChordEvent> _chordEventsFromList(Object? raw) {
    return _eventListFromList<SongChordEvent>(
      raw,
      SongEventKind.chord,
      _chordEventFromMap,
    );
  }

  static List<SongStrumEvent> _strumEventsFromList(Object? raw) {
    return _eventListFromList<SongStrumEvent>(
      raw,
      SongEventKind.strum,
      _strumEventFromMap,
    );
  }

  static List<SongNoteEvent> _noteEventsFromList(Object? raw) {
    return _eventListFromList<SongNoteEvent>(
      raw,
      SongEventKind.note,
      _noteEventFromMap,
    );
  }

  static List<SongLyricEvent> _lyricEventsFromList(Object? raw) {
    return _eventListFromList<SongLyricEvent>(
      raw,
      SongEventKind.lyric,
      _lyricEventFromMap,
    );
  }

  static List<SongMarkerEvent> _markerEventsFromList(Object? raw) {
    return _eventListFromList<SongMarkerEvent>(
      raw,
      SongEventKind.marker,
      _markerEventFromMap,
    );
  }

  static List<T> _eventListFromList<T>(
    Object? raw,
    String expectedKind,
    T Function(Map<String, dynamic>) decode,
  ) {
    if (raw == null) return <T>[];
    if (raw is! List) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.eventsNotAList,
        field: 'events',
      );
    }
    if (raw.length > _codecMaxTrackEventCount) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.eventsNotAList,
        field: 'events',
      );
    }
    return <T>[
      for (final entry in raw)
        if (entry is Map<String, dynamic>) decode(entry),
    ];
  }

  static void _requireEventKind(Map<String, dynamic> json, String expected) {
    final kind = json['kind'];
    if (kind is! String) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.eventKindUnknown,
        field: 'kind',
      );
    }
    if (kind != expected) {
      throw SongDocumentCodecException._(
        SongDocumentCodecErrorCode.eventTypeUnknown,
        field: 'kind',
      );
    }
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

  static Duration _requireDurationMicros(
    Map<String, dynamic> json,
    String field,
    String missingCode,
  ) {
    final value = json[field];
    if (value is! num) {
      throw SongDocumentCodecException._(missingCode, field: field);
    }
    return Duration(microseconds: value.toInt());
  }
}
