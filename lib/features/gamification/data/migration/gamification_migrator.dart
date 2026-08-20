import 'package:strumsight/features/progress/public.dart';

import '../../domain/activity/learning_activity_event.dart';
import '../gamification_repository.dart';
import '../gamification_storage_schema.dart';
import 'legacy_practice_adapter.dart';

/// Immutable summary of one caller-supplied legacy-practice snapshot.
final class LegacyPracticeBackfillReport {
  LegacyPracticeBackfillReport({
    required List<PracticeActivityEvent> events,
    required this.totalStrokes,
    required this.totalChords,
  }) : events = List<PracticeActivityEvent>.unmodifiable(events),
       recordCount = events.length,
       totalSeconds = events.fold<int>(
         0,
         (total, event) => total + event.duration.inSeconds,
       );

  final List<PracticeActivityEvent> events;
  final int recordCount;
  final int totalSeconds;
  final int totalStrokes;
  final int totalChords;
}

/// Backfills a fixed legacy-practice snapshot without retroactive rewards.
///
/// Each successfully mapped event advances the persisted checkpoint to the
/// first unprocessed snapshot index. Mapping is side-effect free apart from
/// this best-effort checkpoint persistence.
final class GamificationMigrator {
  GamificationMigrator({
    required this.gamificationRepository,
    this.adapter = const LegacyPracticeAdapter(),
  });

  final GamificationRepository gamificationRepository;
  final LegacyPracticeAdapter adapter;

  Future<LegacyPracticeBackfillReport> migrate(
    List<PracticeEntry> entries,
  ) async {
    if (entries.length > LegacyPracticeAdapter.maxLegacyEntries) {
      throw ArgumentError.value(
        entries.length,
        'entries.length',
        'A legacy practice snapshot can contain at most '
            '${LegacyPracticeAdapter.maxLegacyEntries} entries.',
      );
    }
    final acceptedEntries = <PracticeEntry>[
      for (final entry in entries)
        if (adapter.accepts(entry)) entry,
    ];
    final events = adapter.adapt(entries);
    final report = LegacyPracticeBackfillReport(
      events: events,
      totalStrokes: acceptedEntries.fold<int>(
        0,
        (total, entry) => total + entry.strokes,
      ),
      totalChords: acceptedEntries.fold<int>(
        0,
        (total, entry) => total + entry.chords,
      ),
    );
    final checkpoint = _checkpointFor(entries.length);

    for (var index = checkpoint; index < entries.length; index++) {
      await gamificationRepository.replaceMigrationState(
        GamificationMigrationState(processedCount: index + 1),
      );
    }

    return report;
  }

  int _checkpointFor(int totalEntryCount) {
    final state = gamificationRepository.readMigrationState();
    final checkpoint = switch (state.status) {
      GamificationReadStatus.missing => 0,
      GamificationReadStatus.available => state.value!.processedCount,
      GamificationReadStatus.corrupt => throw StateError(
        'Cannot resume a corrupt gamification migration checkpoint.',
      ),
    };
    if (checkpoint > totalEntryCount) {
      throw StateError('Migration checkpoint exceeds the supplied snapshot.');
    }
    return checkpoint;
  }
}
