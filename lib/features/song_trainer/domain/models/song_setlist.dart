import 'package:meta/meta.dart';

import 'song_id.dart';
import 'trainer_range.dart';

const int songSetlistSchemaVersion = 1;

/// The execution policy for an entire setlist run.
enum SetlistSessionMode { practice, performance }

/// A recoverable state of an item reference.
enum SetlistItemAvailability {
  ready,
  missingSong,
  missingAsset,
  unsupportedTrack,
  requiresMigration,
  invalidConfig,
}

/// Per-item overrides applied when a setlist launches a song session.
@immutable
final class SetlistItemOverrides {
  const SetlistItemOverrides({
    this.trackId,
    this.range = const FullSongRange(),
    this.speedMultiplier = 1,
    this.loopCount = 1,
    this.countInBars = 1,
    this.pauseAfter = Duration.zero,
    this.capoOverride,
    this.tuningOverrideCode,
  }) : assert(speedMultiplier > 0),
       assert(loopCount > 0),
       assert(countInBars >= 0),
       assert(capoOverride == null || capoOverride >= 0);

  final SongTrackId? trackId;
  final TrainerRange range;
  final double speedMultiplier;
  final int loopCount;
  final int countInBars;
  final Duration pauseAfter;
  final int? capoOverride;
  final String? tuningOverrideCode;

  @override
  bool operator ==(Object other) =>
      other is SetlistItemOverrides &&
      other.trackId == trackId &&
      other.range == range &&
      other.speedMultiplier == speedMultiplier &&
      other.loopCount == loopCount &&
      other.countInBars == countInBars &&
      other.pauseAfter == pauseAfter &&
      other.capoOverride == capoOverride &&
      other.tuningOverrideCode == tuningOverrideCode;

  @override
  int get hashCode => Object.hash(
    trackId,
    range,
    speedMultiplier,
    loopCount,
    countInBars,
    pauseAfter,
    capoOverride,
    tuningOverrideCode,
  );
}

/// A persisted, ordered song reference. Item identity makes duplicates safe.
@immutable
final class SongSetlistItem {
  SongSetlistItem({
    required this.id,
    required this.songId,
    this.overrides = const SetlistItemOverrides(),
    this.initialAvailability = SetlistItemAvailability.ready,
  }) {
    _validateIdentifier(id, field: 'item id');
  }

  final String id;
  final SongId songId;
  final SetlistItemOverrides overrides;
  final SetlistItemAvailability initialAvailability;

  bool get unresolved => initialAvailability != SetlistItemAvailability.ready;

  @override
  bool operator ==(Object other) =>
      other is SongSetlistItem &&
      other.id == id &&
      other.songId == songId &&
      other.overrides == overrides &&
      other.initialAvailability == initialAvailability;

  @override
  int get hashCode => Object.hash(id, songId, overrides, initialAvailability);
}

/// Immutable, versioned Setlist V2 document.
@immutable
final class SongSetlist {
  SongSetlist({
    required this.id,
    required this.name,
    required List<SongSetlistItem> items,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.schemaVersion = songSetlistSchemaVersion,
  }) : items = List<SongSetlistItem>.unmodifiable(items) {
    _validateIdentifier(id, field: 'setlist id');
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Setlist name cannot be empty.');
    }
    if (schemaVersion != songSetlistSchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Unsupported Setlist schema version.',
      );
    }
    if (createdAt.toUtc().isAfter(updatedAt.toUtc())) {
      throw ArgumentError.value(
        (createdAt, updatedAt),
        'timestamps',
        'A setlist cannot be updated before it was created.',
      );
    }
    final itemIds = <String>{};
    for (final item in this.items) {
      if (!itemIds.add(item.id)) {
        throw ArgumentError.value(
          item.id,
          'items',
          'Setlist item ids are unique.',
        );
      }
    }
  }

  final int schemaVersion;
  final String id;
  final String name;
  final List<SongSetlistItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? notes;

  @override
  bool operator ==(Object other) =>
      other is SongSetlist &&
      other.schemaVersion == schemaVersion &&
      other.id == id &&
      other.name == name &&
      _listEquals(other.items, items) &&
      other.createdAt.toUtc() == createdAt.toUtc() &&
      other.updatedAt.toUtc() == updatedAt.toUtc() &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    id,
    name,
    Object.hashAll(items),
    createdAt.toUtc(),
    updatedAt.toUtc(),
    notes,
  );
}

void _validateIdentifier(String value, {required String field}) {
  final valid = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._~-]{0,127}$');
  if (!valid.hasMatch(value)) {
    throw ArgumentError.value(value, field, 'Identifier is not storage-safe.');
  }
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
