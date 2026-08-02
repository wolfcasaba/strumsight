import 'song_id.dart';

/// Stable exception thrown by [SongMarker] validation.
class SongMarkerValidationException implements Exception {
  SongMarkerValidationException._(this.code);

  /// One of [SongMarkerValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'SongMarkerValidationException($code)';
}

/// Stable machine-readable codes emitted by [SongMarker] validation.
abstract final class SongMarkerValidationCode {
  static const String labelEmpty = 'songMarker.label.empty';
  static const String labelTooLong = 'songMarker.label.tooLong';
  static const String measureIndexNegative = 'songMarker.measureIndex.negative';
  static const String measureIndexTooLarge = 'songMarker.measureIndex.tooLarge';
  static const String kindUnknown = 'songMarker.kind.unknown';
  static const String notesTooLong = 'songMarker.notes.tooLong';
}

/// Maximum length of a marker label. Authored; not parsed.
const int maxSongMarkerLabelLength = 128;

/// Maximum length of a marker notes string. Free-form; not parsed.
const int maxSongMarkerNotesLength = 1024;

/// Documented upper bound on a marker's measure index. A song longer than
/// this is almost certainly corrupt.
const int maxSongMarkerMeasureIndex = 1 << 20;

/// Stable, recognised kinds of a [SongMarker]. The kind is a stable,
/// machine-readable code so the UI can pick the right glyph; the [label]
/// remains the user-visible text.
abstract final class SongMarkerKind {
  /// Free-form user note (default kind).
  static const String note = 'note';

  /// Rehearsal mark (verse / chorus / bridge anchor imported from MusicXML
  /// `<rehearsal>` elements).
  static const String rehearsal = 'rehearsal';

  /// Sectional annotation (e.g. "solo starts here").
  static const String section = 'section';

  /// Loop anchor (the user marked a personal practice loop boundary).
  static const String loop = 'loop';

  /// The set of recognised kinds. Adding a new kind requires updating this
  /// list and the UI mapping.
  static const Set<String> known = <String>{note, rehearsal, section, loop};
}

/// One navigational or textual marker anchored on a measure index.
///
/// The document keeps an ordered list of markers; the ordering is preserved
/// by the codec so a decoded document re-renders in the same order as it
/// was authored.
final class SongMarker {
  SongMarker(this.id, String label, this.measureIndex, this.kind, {this.notes})
    : label = _normalizeLabel(label) {
    if (measureIndex < 0) {
      throw SongMarkerValidationException._(
        SongMarkerValidationCode.measureIndexNegative,
      );
    }
    if (measureIndex > maxSongMarkerMeasureIndex) {
      throw SongMarkerValidationException._(
        SongMarkerValidationCode.measureIndexTooLarge,
      );
    }
    if (!SongMarkerKind.known.contains(kind)) {
      throw SongMarkerValidationException._(
        SongMarkerValidationCode.kindUnknown,
      );
    }
    if (notes != null && notes!.length > maxSongMarkerNotesLength) {
      throw SongMarkerValidationException._(
        SongMarkerValidationCode.notesTooLong,
      );
    }
  }

  /// Stable identifier of the marker record.
  final SongMarkerId id;

  /// Non-empty trimmed label. Authored; not parsed.
  final String label;

  /// Zero-based measure index the marker anchors to.
  final int measureIndex;

  /// Stable kind code from [SongMarkerKind].
  final String kind;

  /// Optional free-form notes (locale-independent storage; localised at
  /// display time).
  final String? notes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongMarker &&
          other.id == id &&
          other.label == label &&
          other.measureIndex == measureIndex &&
          other.kind == kind &&
          other.notes == notes;

  @override
  int get hashCode => Object.hash(id, label, measureIndex, kind, notes);

  static String _normalizeLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw SongMarkerValidationException._(
        SongMarkerValidationCode.labelEmpty,
      );
    }
    if (trimmed.length > maxSongMarkerLabelLength) {
      throw SongMarkerValidationException._(
        SongMarkerValidationCode.labelTooLong,
      );
    }
    return trimmed;
  }
}
