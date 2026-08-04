import '../../domain/models/song_practice_record.dart';

/// Result of mapping one old song revision to a new revision.
final class SongRevisionProgressMapping {
  SongRevisionProgressMapping({
    required List<SongPracticeRecord> mapped,
    required List<SongPracticeRecord> archived,
  }) : mapped = List<SongPracticeRecord>.unmodifiable(mapped),
       archived = List<SongPracticeRecord>.unmodifiable(archived);

  final List<SongPracticeRecord> mapped;
  final List<SongPracticeRecord> archived;
}

/// Maps progress only where the target measure identity is unique and explicit.
final class SongRevisionProgressMapper {
  const SongRevisionProgressMapper._();

  static SongRevisionProgressMapping map({
    required List<SongPracticeRecord> records,
    required int targetRevision,
    required Map<String, String> stableMeasureIds,
  }) {
    if (targetRevision < 0) {
      throw ArgumentError.value(
        targetRevision,
        'targetRevision',
        'Cannot be negative.',
      );
    }
    final targetCounts = <String, int>{};
    for (final target in stableMeasureIds.values) {
      targetCounts[target] = (targetCounts[target] ?? 0) + 1;
    }
    final mapped = <SongPracticeRecord>[];
    final archived = <SongPracticeRecord>[];
    for (final record in records) {
      final targetMeasureId = stableMeasureIds[record.source.measureId];
      if (targetMeasureId == null || targetCounts[targetMeasureId] != 1) {
        archived.add(record.copyWith(isArchived: true));
        continue;
      }
      mapped.add(
        record.copyWith(
          songRevision: targetRevision,
          source: SongProgressSource(
            measureId: targetMeasureId,
            eventId: record.source.eventId,
            measureIndex: record.source.measureIndex,
            sectionId: record.source.sectionId,
          ),
          isArchived: false,
        ),
      );
    }
    mapped.sort((left, right) => left.id.compareTo(right.id));
    archived.sort((left, right) => left.id.compareTo(right.id));
    return SongRevisionProgressMapping(mapped: mapped, archived: archived);
  }
}
