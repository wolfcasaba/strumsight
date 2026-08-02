import 'song_asset_reference.dart';
import 'song_id.dart';
import 'song_marker.dart';
import 'song_metadata.dart';
import 'song_source.dart';

/// Stable exceptions for [SongDocument] construction.
class SongDocumentValidationException implements Exception {
  SongDocumentValidationException._(this.code);

  /// One of [SongDocumentValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'SongDocumentValidationException($code)';
}

/// Stable machine-readable codes emitted by [SongDocument] validation.
abstract final class SongDocumentValidationCode {
  static const String schemaVersionOutOfRange =
      'songDocument.schemaVersion.outOfRange';
  static const String revisionNegative = 'songDocument.revision.negative';
  static const String createdAfterUpdated =
      'songDocument.createdAt.afterUpdatedAt';
  static const String assetsTooMany = 'songDocument.assets.tooMany';
  static const String markersTooMany = 'songDocument.markers.tooMany';
}

/// Documented upper bound on the number of asset references one document
/// can carry. A realistic backing track + artwork + a few chord-chart
/// excerpts fit comfortably under this; anything beyond is almost
/// certainly corrupt.
const int maxSongDocumentAssetCount = 64;

/// Documented upper bound on the number of markers one document can carry.
const int maxSongDocumentMarkerCount = 1024;

/// The lowest schema version the codec knows how to read.
///
/// Bumped ONLY on a wire-incompatible change; a future bump rejects older
/// documents at decode time (the repository logs and quarantines them —
/// the user's other documents survive).
const int songDocumentSchemaVersion = 1;

/// Immutable, versioned V2 song document (ADR 0089, SDD §9.1).
///
/// The full §9.1 surface — sections, measures, tracks, tempo / meter / key
/// maps — is added in E03-R03 and E03-R04. This minimal skeleton covers
/// identity, metadata, source provenance, optional asset references and
/// markers, and the `schemaVersion` / `revision` / timestamp envelope the
/// repository and codec need.
final class SongDocument {
  SongDocument({
    required this.schemaVersion,
    required this.id,
    required this.revision,
    required this.metadata,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    List<SongAssetReference>? assets,
    List<SongMarker>? markers,
  }) : assets = List<SongAssetReference>.unmodifiable(
         assets ?? const <SongAssetReference>[],
       ),
       markers = List<SongMarker>.unmodifiable(
         markers ?? const <SongMarker>[],
       ) {
    if (schemaVersion < songDocumentSchemaVersion) {
      throw SongDocumentValidationException._(
        SongDocumentValidationCode.schemaVersionOutOfRange,
      );
    }
    if (revision < 0) {
      throw SongDocumentValidationException._(
        SongDocumentValidationCode.revisionNegative,
      );
    }
    final createdUtc = createdAt.toUtc();
    final updatedUtc = updatedAt.toUtc();
    if (createdUtc.isAfter(updatedUtc)) {
      throw SongDocumentValidationException._(
        SongDocumentValidationCode.createdAfterUpdated,
      );
    }
    if (this.assets.length > maxSongDocumentAssetCount) {
      throw SongDocumentValidationException._(
        SongDocumentValidationCode.assetsTooMany,
      );
    }
    if (this.markers.length > maxSongDocumentMarkerCount) {
      throw SongDocumentValidationException._(
        SongDocumentValidationCode.markersTooMany,
      );
    }
  }

  /// Wire-incompatible schema version. Bumped on a breaking change.
  final int schemaVersion;

  /// Stable, locally-generated identifier (ADR 0089 §Döntés 2).
  final SongId id;

  /// Monotonic optimistic-concurrency counter (ADR 0089 §Döntés 3). Bumped
  /// on every successful write; the repository checks `expectedRevision`
  /// before applying a change.
  final int revision;

  /// Authoring metadata.
  final SongMetadata metadata;

  /// Provenance chain.
  final SongSource source;

  /// Optional asset references. Unmodifiable view — see [List.unmodifiable].
  final List<SongAssetReference> assets;

  /// Optional markers. Unmodifiable view — see [List.unmodifiable].
  final List<SongMarker> markers;

  /// Original creation timestamp. Compared in UTC; persisted as UTC ISO-8601
  /// by the codec (SDD §9.4 / §5 kötött döntések 2).
  final DateTime createdAt;

  /// Last update timestamp. Compared in UTC; persisted as UTC ISO-8601.
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongDocument &&
          other.schemaVersion == schemaVersion &&
          other.id == id &&
          other.revision == revision &&
          other.metadata == metadata &&
          other.source == source &&
          _listEquals(other.assets, assets) &&
          _listEquals(other.markers, markers) &&
          other.createdAt.toUtc().microsecondsSinceEpoch ==
              createdAt.toUtc().microsecondsSinceEpoch &&
          other.updatedAt.toUtc().microsecondsSinceEpoch ==
              updatedAt.toUtc().microsecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    id,
    revision,
    metadata,
    source,
    Object.hashAll(assets),
    Object.hashAll(markers),
    createdAt.toUtc().microsecondsSinceEpoch,
    updatedAt.toUtc().microsecondsSinceEpoch,
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
