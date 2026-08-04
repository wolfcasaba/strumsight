import 'song_id.dart';
import 'song_section.dart';

/// An immutable source position selected for a future trainer session.
///
/// A range is intentionally expressed in song-domain measure coordinates.
/// Presentation may use inclusive labels, but every resolved range ends
/// exclusively so the session compiler receives one unambiguous interval.
sealed class TrainerRange {
  const TrainerRange();

  /// Resolves this selection against the currently loaded song structure.
  ///
  /// A `null` result means that the selection is stale or outside the song
  /// bounds. Callers must disable session creation instead of clamping it.
  MeasureRange? resolve({
    required int measureCount,
    required List<SongSection> sections,
  });
}

/// Selects every measure in the song.
final class FullSongRange extends TrainerRange {
  const FullSongRange();

  @override
  MeasureRange? resolve({
    required int measureCount,
    required List<SongSection> sections,
  }) => measureCount > 0
      ? MeasureRange(start: 0, endExclusive: measureCount)
      : null;

  @override
  bool operator ==(Object other) => other is FullSongRange;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Selects the current extent of a named section.
final class SectionRange extends TrainerRange {
  SectionRange(this.sectionId);

  final SongSectionId sectionId;

  @override
  MeasureRange? resolve({
    required int measureCount,
    required List<SongSection> sections,
  }) {
    for (final section in sections) {
      if (section.id != sectionId) continue;
      final range = MeasureRange(
        start: section.startMeasure,
        endExclusive: section.endMeasureExclusive,
      );
      return range.resolve(measureCount: measureCount, sections: sections);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SectionRange && other.sectionId == sectionId;

  @override
  int get hashCode => sectionId.hashCode;
}

/// A closed-open measure interval, `[start, endExclusive)`.
final class MeasureRange extends TrainerRange {
  MeasureRange({required this.start, required this.endExclusive}) {
    if (start < 0 || endExclusive <= start) {
      throw ArgumentError.value(
        (start, endExclusive),
        'range',
        'Measure range must have a non-negative start and a later end.',
      );
    }
  }

  /// Maps the inclusive bounds selected by the UI into the domain interval.
  factory MeasureRange.fromInclusive({
    required int start,
    required int endInclusive,
  }) {
    if (start < 0 || endInclusive < start) {
      throw ArgumentError.value(
        (start, endInclusive),
        'range',
        'Inclusive measure range must not be empty or negative.',
      );
    }
    return MeasureRange(start: start, endExclusive: endInclusive + 1);
  }

  final int start;
  final int endExclusive;

  @override
  MeasureRange? resolve({
    required int measureCount,
    required List<SongSection> sections,
  }) => measureCount >= endExclusive ? this : null;

  @override
  bool operator ==(Object other) =>
      other is MeasureRange &&
      other.start == start &&
      other.endExclusive == endExclusive;

  @override
  int get hashCode => Object.hash(start, endExclusive);
}

/// A saved selection tied to the immutable song identity and revision it was
/// created from. A later revision must resolve it again before use.
final class BookmarkRange extends TrainerRange {
  BookmarkRange({
    required this.songId,
    required this.songRevision,
    required this.range,
  }) {
    if (songRevision < 0) {
      throw ArgumentError.value(
        songRevision,
        'songRevision',
        'A bookmark revision cannot be negative.',
      );
    }
    if (range is BookmarkRange) {
      throw ArgumentError.value(
        range,
        'range',
        'A bookmark cannot contain another bookmark.',
      );
    }
  }

  final SongId songId;
  final int songRevision;
  final TrainerRange range;

  /// Whether this bookmark was created for the exact document revision being
  /// configured. A matching identifier alone is not enough after an edit.
  bool matchesSong({required SongId songId, required int revision}) =>
      this.songId == songId && songRevision == revision;

  @override
  MeasureRange? resolve({
    required int measureCount,
    required List<SongSection> sections,
  }) => range.resolve(measureCount: measureCount, sections: sections);

  @override
  bool operator ==(Object other) =>
      other is BookmarkRange &&
      other.songId == songId &&
      other.songRevision == songRevision &&
      other.range == range;

  @override
  int get hashCode => Object.hash(songId, songRevision, range);
}
