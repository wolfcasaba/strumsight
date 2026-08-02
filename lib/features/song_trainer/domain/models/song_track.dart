import 'package:meta/meta.dart';

import 'song_event.dart';
import 'song_id.dart';
import 'song_instrument.dart';

/// Stable exception thrown by any [SongTrack] subtype constructor.
class SongTrackConstructionException implements Exception {
  SongTrackConstructionException._(this.code);

  /// One of [SongTrackConstructionCode]'s constants.
  final String code;

  @override
  String toString() => 'SongTrackConstructionException($code)';
}

/// Stable machine-readable codes emitted by [SongTrack] construction.
abstract final class SongTrackConstructionCode {
  static const String nameEmpty = 'songTrack.name.empty';
  static const String nameTooLong = 'songTrack.name.tooLong';
  static const String tooManyEvents = 'songTrack.events.tooMany';
}

/// Documented upper bound on the number of events any single track can
/// carry. Anything beyond is almost certainly corrupt — the analyzer
/// would have to walk O(n²) pairs.
const int maxSongTrackEventCount = 1 << 16;

/// Documented upper bound on a track display name. Generous next to any
/// realistic author label; rejects obvious garbage.
const int maxSongTrackNameLength = 128;

/// Stable machine-readable codes emitted by the [SongTrack] codec layer
/// (used by `SongDocumentCodec`). Lives here so track subtyping stays
/// reviewable in a single file.
abstract final class SongTrackKind {
  static const String chord = 'chord';
  static const String strum = 'strum';
  static const String note = 'note';
  static const String lyrics = 'lyrics';
  static const String marker = 'marker';
  static const String backingAudio = 'backingAudio';
}

/// Stable machine-readable codes emitted by the [SongEvent] codec layer.
abstract final class SongEventKind {
  static const String chord = 'chord';
  static const String strum = 'strum';
  static const String note = 'note';
  static const String lyric = 'lyric';
  static const String marker = 'marker';
}

/// Sealed track hierarchy (SDD §11.1).
///
/// Every track carries a stable identifier, a user-visible name, the
/// [SongInstrument] it is played on, and an enabled flag the UI toggles
/// without losing the underlying event data. Subtypes add an immutable
/// events list (or asset reference for [BackingAudioTrack], which lives
/// in `backing_audio_track.dart`).
sealed class SongTrack {
  SongTrack({
    required this.id,
    required String name,
    required this.instrument,
    required this.enabled,
  }) : name = _normalizeName(name);

  /// Stable, locally-generated identifier.
  final SongTrackId id;

  /// Trimmed, non-empty display name.
  final String name;

  /// Canonical instrument reference (name + optional tuning).
  final SongInstrument instrument;

  /// UI toggle: a disabled track is not played and never participates in
  /// analysis. Stored on every track so the codec survives a future
  /// enable-toggle without schema churn.
  final bool enabled;

  static String _normalizeName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw SongTrackConstructionException._(
        SongTrackConstructionCode.nameEmpty,
      );
    }
    if (trimmed.length > maxSongTrackNameLength) {
      throw SongTrackConstructionException._(
        SongTrackConstructionCode.nameTooLong,
      );
    }
    return trimmed;
  }
}

/// Immutable list of chord events (SDD §11.1 + §11.2).
@immutable
final class ChordTrack extends SongTrack {
  ChordTrack({
    required super.id,
    required super.name,
    required super.instrument,
    super.enabled = true,
    required List<SongChordEvent> events,
  }) : events = _freezeEvents<SongChordEvent>(
         events,
         SongTrackConstructionCode.tooManyEvents,
       );

  /// Chord events the track carries. The returned list is unmodifiable;
  /// the codec preserves the canonical (start, track, id) order.
  final List<SongChordEvent> events;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChordTrack &&
          other.id == id &&
          other.name == name &&
          other.instrument == instrument &&
          other.enabled == enabled &&
          _listEquals(other.events, events);

  @override
  int get hashCode =>
      Object.hash(id, name, instrument, enabled, Object.hashAll(events));
}

/// Immutable list of strum events (SDD §11.1 + §11.3).
@immutable
final class StrumTrack extends SongTrack {
  StrumTrack({
    required super.id,
    required super.name,
    required super.instrument,
    super.enabled = true,
    required List<SongStrumEvent> events,
  }) : events = _freezeEvents<SongStrumEvent>(
         events,
         SongTrackConstructionCode.tooManyEvents,
       );

  /// Strum events the track carries. The returned list is unmodifiable;
  /// the codec preserves the canonical (at, track, id) order.
  final List<SongStrumEvent> events;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrumTrack &&
          other.id == id &&
          other.name == name &&
          other.instrument == instrument &&
          other.enabled == enabled &&
          _listEquals(other.events, events);

  @override
  int get hashCode =>
      Object.hash(id, name, instrument, enabled, Object.hashAll(events));
}

/// Immutable list of note events (SDD §11.1 + §11.4).
@immutable
final class NoteTrack extends SongTrack {
  NoteTrack({
    required super.id,
    required super.name,
    required super.instrument,
    super.enabled = true,
    required List<SongNoteEvent> events,
  }) : events = _freezeEvents<SongNoteEvent>(
         events,
         SongTrackConstructionCode.tooManyEvents,
       );

  /// Note events the track carries. The returned list is unmodifiable;
  /// the codec preserves the canonical (start, track, id) order.
  final List<SongNoteEvent> events;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteTrack &&
          other.id == id &&
          other.name == name &&
          other.instrument == instrument &&
          other.enabled == enabled &&
          _listEquals(other.events, events);

  @override
  int get hashCode =>
      Object.hash(id, name, instrument, enabled, Object.hashAll(events));
}

/// Immutable list of lyric events (SDD §11.1 + §11.6).
@immutable
final class LyricsTrack extends SongTrack {
  LyricsTrack({
    required super.id,
    required super.name,
    required super.instrument,
    super.enabled = true,
    required List<SongLyricEvent> events,
  }) : events = _freezeEvents<SongLyricEvent>(
         events,
         SongTrackConstructionCode.tooManyEvents,
       );

  /// Lyric events the track carries. The returned list is unmodifiable.
  final List<SongLyricEvent> events;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsTrack &&
          other.id == id &&
          other.name == name &&
          other.instrument == instrument &&
          other.enabled == enabled &&
          _listEquals(other.events, events);

  @override
  int get hashCode =>
      Object.hash(id, name, instrument, enabled, Object.hashAll(events));
}

/// Immutable list of marker events (SDD §11.1 + §11.6).
@immutable
final class MarkerTrack extends SongTrack {
  MarkerTrack({
    required super.id,
    required super.name,
    required super.instrument,
    super.enabled = true,
    required List<SongMarkerEvent> events,
  }) : events = _freezeEvents<SongMarkerEvent>(
         events,
         SongTrackConstructionCode.tooManyEvents,
       );

  /// Marker events the track carries. The returned list is unmodifiable.
  final List<SongMarkerEvent> events;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerTrack &&
          other.id == id &&
          other.name == name &&
          other.instrument == instrument &&
          other.enabled == enabled &&
          _listEquals(other.events, events);

  @override
  int get hashCode =>
      Object.hash(id, name, instrument, enabled, Object.hashAll(events));
}

List<T> _freezeEvents<T>(List<T> events, String tooManyCode) {
  if (events.length > maxSongTrackEventCount) {
    throw SongTrackConstructionException._(tooManyCode);
  }
  return List<T>.unmodifiable(events);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// BackingAudioTrack (SDD §11.7).
//
// Lives here (and not in `backing_audio_track.dart`) so the sealed
// [SongTrack] hierarchy stays in a single library — Dart 3 sealed requires
// every direct subclass to share a library with the base class. The
// dedicated file is preserved as a `show` re-export for callers that
// import the subtype directly.
// ---------------------------------------------------------------------------

/// Documented bounds on a backing-audio gain value. ±60 dB of headroom is
/// more than enough for any realistic mix — anything outside is almost
/// certainly corrupt.
const double minSongBackingGainDb = -60;
const double maxSongBackingGainDb = 24;

/// A backing-audio track (SDD §11.7).
///
/// The track deliberately stores an asset REFERENCE ([assetId]) and not a
/// platform path: the repository resolves the asset to a playable file
/// when the user actually presses play (§5 kötött döntés 3). [gridOffset]
/// lets the user pre-roll the backing track against the song grid;
/// [gainDb] carries the authored mix.
@immutable
final class BackingAudioTrack extends SongTrack {
  BackingAudioTrack({
    required super.id,
    required super.name,
    required super.instrument,
    required this.assetId,
    required Duration gridOffset,
    this.gainDb = 0,
    super.enabled = true,
  }) : gridOffset = _normalizeOffset(gridOffset) {
    if (!gainDb.isFinite) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeStart,
        field: 'gainDb',
      );
    }
    if (gainDb < minSongBackingGainDb || gainDb > maxSongBackingGainDb) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeStart,
        field: 'gainDb',
      );
    }
  }

  /// Stable asset reference the repository resolves to bytes.
  final SongAssetId assetId;

  /// Pre-roll offset of the backing track against the song grid. Negative
  /// offsets are clamped to zero.
  final Duration gridOffset;

  /// Authored mix gain in decibels. Defaults to unity (0 dB).
  final double gainDb;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackingAudioTrack &&
          other.id == id &&
          other.name == name &&
          other.instrument == instrument &&
          other.enabled == enabled &&
          other.assetId == assetId &&
          other.gridOffset == gridOffset &&
          other.gainDb == gainDb;

  @override
  int get hashCode =>
      Object.hash(id, name, instrument, enabled, assetId, gridOffset, gainDb);

  static Duration _normalizeOffset(Duration value) {
    if (value.isNegative) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeStart,
        field: 'gridOffset',
      );
    }
    return value;
  }
}
