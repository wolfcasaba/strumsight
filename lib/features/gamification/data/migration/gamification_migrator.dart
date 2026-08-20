import 'package:strumsight/features/progress/public.dart';

import '../../domain/activity/learning_activity_event.dart';
import '../../domain/rewards/reward_ledger_entry.dart';
import '../../domain/rewards/reward_reason.dart';
import '../gamification_repository.dart';
import '../gamification_storage_schema.dart';
import '../reward_ledger_repository.dart';
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
/// Each successful ledger append advances the persisted checkpoint to the
/// first unprocessed snapshot index. A ledger duplicate is also success: its
/// stable source-event id proves the receipt already exists.
final class GamificationMigrator {
  GamificationMigrator({
    required this.gamificationRepository,
    required this.rewardLedgerRepository,
    this.adapter = const LegacyPracticeAdapter(),
  });

  final GamificationRepository gamificationRepository;
  final RewardLedgerRepository rewardLedgerRepository;
  final LegacyPracticeAdapter adapter;

  Future<LegacyPracticeBackfillReport> migrate(
    List<PracticeEntry> entries,
  ) async {
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
    final checkpoint = _checkpointFor(events.length);

    for (var index = checkpoint; index < events.length; index++) {
      final event = events[index];
      await rewardLedgerRepository.appendIfAbsent(_zeroXpReceipt(event));
      await gamificationRepository.replaceMigrationState(
        GamificationMigrationState(processedCount: index + 1),
      );
    }

    return report;
  }

  int _checkpointFor(int eventCount) {
    final state = gamificationRepository.readMigrationState();
    final checkpoint = switch (state.status) {
      GamificationReadStatus.missing => 0,
      GamificationReadStatus.available => state.value!.processedCount,
      GamificationReadStatus.corrupt => throw StateError(
        'Cannot resume a corrupt gamification migration checkpoint.',
      ),
    };
    if (checkpoint > eventCount) {
      throw StateError('Migration checkpoint exceeds the supplied snapshot.');
    }
    return checkpoint;
  }

  RewardLedgerEntry _zeroXpReceipt(PracticeActivityEvent event) =>
      RewardLedgerEntry(
        ledgerId: 'legacy-receipt/${event.eventId}',
        sourceEventId: event.eventId,
        createdAt: event.occurredAt,
        schemaVersion: rewardLedgerEntrySchemaVersion,
        policyVersion: 1,
        baseXp: 0,
        bonusXp: 0,
        totalXp: 0,
        reasonCodes: const <RewardReason>[],
      );
}
