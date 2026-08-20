import 'package:strumsight/features/progress/public.dart';

import '../../domain/activity/activity_source.dart';
import '../../domain/activity/evidence_trust.dart';
import '../../domain/activity/learning_activity_event.dart';

/// Converts a fixed legacy-practice snapshot into canonical activity events.
///
/// The caller supplies the snapshot in its persisted `newestLast` order. An
/// occurrence ordinal scoped to an entry's stable wire fingerprint preserves
/// exact duplicate sessions while keeping event ids deterministic on replay.
final class LegacyPracticeAdapter {
  const LegacyPracticeAdapter();

  List<PracticeActivityEvent> adapt(List<PracticeEntry> entries) {
    final occurrences = <String, int>{};
    final events = <PracticeActivityEvent>[];

    for (final entry in entries) {
      if (!accepts(entry)) continue;

      final fingerprint = _fingerprint(entry);
      final ordinal = occurrences[fingerprint] ?? 0;
      occurrences[fingerprint] = ordinal + 1;
      events.add(_eventFor(entry, fingerprint, ordinal));
    }

    return List<PracticeActivityEvent>.unmodifiable(events);
  }

  /// Whether [entry] is safe to represent as a canonical activity event.
  bool accepts(PracticeEntry entry) =>
      entry.seconds >= 0 &&
      entry.strokes >= 0 &&
      entry.chords >= 0 &&
      (entry.directionAccuracy == null ||
          (entry.directionAccuracy!.isFinite &&
              entry.directionAccuracy! >= 0 &&
              entry.directionAccuracy! <= 1));

  PracticeActivityEvent _eventFor(
    PracticeEntry entry,
    String fingerprint,
    int ordinal,
  ) {
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      entry.day * Duration.millisecondsPerDay,
      isUtc: true,
    );
    return PracticeActivityEvent(
      eventId: 'legacy-practice/v1/$fingerprint/$ordinal',
      occurredAt: occurredAt,
      epochDay: entry.day,
      source: _activitySource(entry.source),
      trust: EvidenceTrust.unverified,
      schemaVersion: learningActivityEventSchemaVersion,
      duration: Duration(seconds: entry.seconds),
      score: entry.directionAccuracy ?? 0,
    );
  }

  String _fingerprint(PracticeEntry entry) =>
      '${entry.day}:${entry.source.name}:${entry.seconds}:${entry.strokes}:'
      '${entry.chords}:${entry.directionAccuracy?.toString() ?? 'null'}';

  ActivitySource _activitySource(PracticeSource source) => switch (source) {
    PracticeSource.live => ActivitySource.live,
    PracticeSource.analyze => ActivitySource.analyze,
    PracticeSource.learn => ActivitySource.learn,
  };
}
