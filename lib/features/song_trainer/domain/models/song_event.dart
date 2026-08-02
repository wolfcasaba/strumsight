import 'package:meta/meta.dart';

import '../../../../core/music/chord.dart';
import '../../../../core/music/strum.dart';
import 'song_id.dart';
import 'song_marker.dart';
import 'song_note_technique.dart';

/// Stable exception thrown by any [SongEvent] subtype constructor.
class SongTrackValidationException implements Exception {
  SongTrackValidationException(this.code, {this.field});

  /// One of [SongTrackValidationCode]'s constants.
  final String code;

  /// Field that failed when the failure is scoped to one.
  final String? field;

  @override
  String toString() =>
      'SongTrackValidationException($code${field == null ? '' : ', field: $field'})';
}

/// Stable machine-readable codes emitted by song-event validation.
abstract final class SongTrackValidationCode {
  static const String negativeStart = 'songEvent.start.negative';
  static const String zeroOrNegativeDuration =
      'songEvent.duration.zeroOrNegative';
  static const String negativeAt = 'songEvent.at.negative';
  static const String midiPitchOutOfRange = 'songEvent.midiPitch.outOfRange';
  static const String negativeFret = 'songEvent.fret.negative';
  static const String stringFretMismatch =
      'songEvent.stringIndex.fret.mismatch';
  static const String negativeVelocity = 'songEvent.velocity.negative';
  static const String negativeStringIndex = 'songEvent.stringIndex.negative';
  static const String lyricTextEmpty = 'songEvent.lyric.text.empty';
  static const String lyricTextTooLong = 'songEvent.lyric.text.tooLong';
  static const String markerLabelEmpty = 'songEvent.marker.label.empty';
  static const String markerLabelTooLong = 'songEvent.marker.label.tooLong';
  static const String markerKindUnknown = 'songEvent.marker.kind.unknown';
}

/// Documented upper bound on the number of techniques attached to a note.
const int maxSongNoteTechniqueCount = 8;

/// Documented upper bound on a single lyric line length.
const int maxSongLyricTextLength = 1024;

/// Documented upper bound on a marker-event label.
const int maxSongMarkerEventLabelLength = 128;

/// Documented upper bound on a note velocity (MIDI convention).
const int maxSongNoteVelocity = 127;

/// Documented upper bound on a 6-string guitar stringIndex.
const int maxSongNoteStringIndex = 5;

/// Maximum number of frets a standard guitar has.
const int maxSongNoteFret = 24;

/// A chord event anchored on a song timeline (SDD §11.2).
///
/// The [symbol] is a core [Chord] value object (an unvalidated label
/// wrapper) so unsupported chord notations — including exotic jazz
/// extensions — survive the round-trip without data loss
/// (ADR 0113 §Döntés 1). The optional [displayText] carries the original
/// source label when the importer could not normalise the symbol.
@immutable
final class SongChordEvent {
  SongChordEvent({
    required this.id,
    required this.start,
    required this.duration,
    required this.symbol,
    this.displayText,
  }) {
    if (start.isNegative) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeStart,
        field: 'start',
      );
    }
    if (duration <= Duration.zero) {
      throw SongTrackValidationException(
        SongTrackValidationCode.zeroOrNegativeDuration,
        field: 'duration',
      );
    }
    if (displayText != null && displayText!.isEmpty) {
      throw SongTrackValidationException(
        SongTrackValidationCode.markerLabelEmpty,
        field: 'displayText',
      );
    }
  }

  /// Stable, locally-generated identifier.
  final SongEventId id;

  /// Inclusive start anchor on the track timeline. Must be non-negative.
  final Duration start;

  /// Exclusive end anchor minus [start]. Must be strictly positive.
  final Duration duration;

  /// Chord symbol in its normalised form. The [Chord] is an unvalidated
  /// label wrapper — unsupported notations are preserved verbatim
  /// (ADR 0113 §Döntés 1).
  final Chord symbol;

  /// Original source label preserved for round-trip fidelity. `null` when
  /// the importer produced a normalised symbol only.
  final String? displayText;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongChordEvent &&
          other.id == id &&
          other.start == start &&
          other.duration == duration &&
          other.symbol == symbol &&
          other.displayText == displayText;

  @override
  int get hashCode => Object.hash(id, start, duration, symbol, displayText);
}

/// A strum event anchored on a song timeline (SDD §11.3).
///
/// [direction] is `null` when the importer could not determine the stroke
/// direction (the SDD "unknown" state); the rhythm-scoring path can still
/// consume the event as an onset, only the direction-scoring path refuses
/// to score it (ADR 0113 §Döntés 3).
@immutable
final class SongStrumEvent {
  SongStrumEvent({
    required this.id,
    required this.at,
    required this.direction,
    this.accent = false,
    this.muted = false,
    this.targetChordId,
  }) {
    if (at.isNegative) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeAt,
        field: 'at',
      );
    }
  }

  /// Stable, locally-generated identifier.
  final SongEventId id;

  /// Inclusive time anchor on the track timeline. Must be non-negative.
  final Duration at;

  /// Stroke direction, or `null` (= unknown — see class doc).
  final StrumDirection? direction;

  /// Accented stroke (notated ">") — louder attack.
  final bool accent;

  /// Muted / dampened stroke (notated "x") — percussive, no pitched
  /// content.
  final bool muted;

  /// Optional pointer back to a [SongChordEvent] this stroke belongs to.
  final SongEventId? targetChordId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongStrumEvent &&
          other.id == id &&
          other.at == at &&
          other.direction == direction &&
          other.accent == accent &&
          other.muted == muted &&
          other.targetChordId == targetChordId;

  @override
  int get hashCode =>
      Object.hash(id, at, direction, accent, muted, targetChordId);
}

/// A pitched note event anchored on a song timeline (SDD §11.4).
///
/// The [midiPitch] is the canonical scoring input. Optional [stringIndex]
/// and [fret] capture the original tablature reading; the constructor
/// enforces the "either both or neither" rule the SDD requires.
@immutable
final class SongNoteEvent {
  SongNoteEvent({
    required this.id,
    required this.start,
    required this.duration,
    required this.midiPitch,
    this.velocity,
    this.stringIndex,
    this.fret,
    this.tieGroupId,
    this.techniques = const <SongNoteTechnique>{},
  }) {
    if (start.isNegative) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeStart,
        field: 'start',
      );
    }
    if (duration <= Duration.zero) {
      throw SongTrackValidationException(
        SongTrackValidationCode.zeroOrNegativeDuration,
        field: 'duration',
      );
    }
    if (midiPitch < 0 || midiPitch > 127) {
      throw SongTrackValidationException(
        SongTrackValidationCode.midiPitchOutOfRange,
        field: 'midiPitch',
      );
    }
    if (velocity != null) {
      if (velocity! < 0 || velocity! > maxSongNoteVelocity) {
        throw SongTrackValidationException(
          SongTrackValidationCode.negativeVelocity,
          field: 'velocity',
        );
      }
    }
    final hasString = stringIndex != null;
    final hasFret = fret != null;
    if (hasString != hasFret) {
      throw SongTrackValidationException(
        SongTrackValidationCode.stringFretMismatch,
      );
    }
    if (hasString && stringIndex! < 0) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeStringIndex,
        field: 'stringIndex',
      );
    }
    if (hasString && stringIndex! > maxSongNoteStringIndex) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeStringIndex,
        field: 'stringIndex',
      );
    }
    if (hasFret && fret! < 0) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeFret,
        field: 'fret',
      );
    }
    if (hasFret && fret! > maxSongNoteFret) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeFret,
        field: 'fret',
      );
    }
    if (techniques.length > maxSongNoteTechniqueCount) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeStart,
        field: 'techniques',
      );
    }
  }

  /// Stable, locally-generated identifier.
  final SongEventId id;

  /// Inclusive start anchor on the track timeline. Must be non-negative.
  final Duration start;

  /// Duration of the note on the track timeline. Must be strictly positive.
  final Duration duration;

  /// Canonical scoring input. MIDI 0–127 inclusive.
  final int midiPitch;

  /// Optional MIDI velocity (0..127). `null` when the importer did not
  /// record one.
  final int? velocity;

  /// Original tablature string index (0 = lowest pitched string). Always
  /// paired with [fret] — see class doc.
  final int? stringIndex;

  /// Original tablature fret. Always paired with [stringIndex].
  final int? fret;

  /// Optional tie-group identifier. Notes that share an id belong to the
  /// same musical tie; mismatched pitches inside one group are reported by
  /// the [NoteTrackAnalyzer] as a warning (SDD §11.4).
  final String? tieGroupId;

  /// Optional set of performance techniques. Persisted as data; an
  /// unknown technique does NOT grant scoring capability
  /// (SDD §11.4 + §5 kötött döntés 2).
  final Set<SongNoteTechnique> techniques;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SongNoteEvent) return false;
    if (other.id != id ||
        other.start != start ||
        other.duration != duration ||
        other.midiPitch != midiPitch ||
        other.velocity != velocity ||
        other.stringIndex != stringIndex ||
        other.fret != fret ||
        other.tieGroupId != tieGroupId) {
      return false;
    }
    if (other.techniques.length != techniques.length) return false;
    for (final technique in techniques) {
      if (!other.techniques.contains(technique)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    start,
    duration,
    midiPitch,
    velocity,
    stringIndex,
    fret,
    tieGroupId,
    Object.hashAllUnordered(techniques),
  );
}

/// A lyric event — display and navigation only, never scored
/// (SDD §11.6 + §5 kötött döntés 3).
@immutable
final class SongLyricEvent {
  SongLyricEvent({required this.id, required this.at, required this.text}) {
    if (at.isNegative) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeAt,
        field: 'at',
      );
    }
    if (text.isEmpty) {
      throw SongTrackValidationException(
        SongTrackValidationCode.lyricTextEmpty,
        field: 'text',
      );
    }
    if (text.length > maxSongLyricTextLength) {
      throw SongTrackValidationException(
        SongTrackValidationCode.lyricTextTooLong,
        field: 'text',
      );
    }
  }

  /// Stable, locally-generated identifier.
  final SongEventId id;

  /// Inclusive time anchor on the track timeline. Must be non-negative.
  final Duration at;

  /// Display text. Free-form UTF-8; not parsed.
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongLyricEvent &&
          other.id == id &&
          other.at == at &&
          other.text == text;

  @override
  int get hashCode => Object.hash(id, at, text);
}

/// A navigation marker event — display and routing only, never scored.
@immutable
final class SongMarkerEvent {
  SongMarkerEvent({
    required this.id,
    required this.at,
    required this.label,
    required this.kind,
    this.notes,
  }) {
    if (at.isNegative) {
      throw SongTrackValidationException(
        SongTrackValidationCode.negativeAt,
        field: 'at',
      );
    }
    if (label.isEmpty) {
      throw SongTrackValidationException(
        SongTrackValidationCode.markerLabelEmpty,
        field: 'label',
      );
    }
    if (label.length > maxSongMarkerEventLabelLength) {
      throw SongTrackValidationException(
        SongTrackValidationCode.markerLabelTooLong,
        field: 'label',
      );
    }
    if (!SongMarkerKind.known.contains(kind)) {
      throw SongTrackValidationException(
        SongTrackValidationCode.markerKindUnknown,
        field: 'kind',
      );
    }
  }

  /// Stable, locally-generated identifier.
  final SongEventId id;

  /// Inclusive time anchor on the track timeline. Must be non-negative.
  final Duration at;

  /// Trimmed, non-empty label.
  final String label;

  /// Stable kind code from [SongMarkerKind].
  final String kind;

  /// Optional free-form notes.
  final String? notes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongMarkerEvent &&
          other.id == id &&
          other.at == at &&
          other.label == label &&
          other.kind == kind &&
          other.notes == notes;

  @override
  int get hashCode => Object.hash(id, at, label, kind, notes);
}
