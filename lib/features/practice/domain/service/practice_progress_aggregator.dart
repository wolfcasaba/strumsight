import 'package:meta/meta.dart';

import '../../../progress/public.dart';
import '../../domain/model/practice_history_entry.dart';
import '../../domain/model/practice_metrics.dart';

/// A normalised, source-agnostic snapshot of one finished practice session,
/// produced by [PracticeProgressAggregator.aggregate].
///
/// Unifies V1 [PracticeEntry] (nullable direction accuracy, no other metrics)
/// with V2 [PracticeHistoryEntry] (full MetricValue per dimension). Every
/// dimension that V1 did not record is reported as [MetricNotApplicable] —
/// never fabricated as `0.0` or any other false value (ADR 0085 Döntés 2,
/// brief A1).
@immutable
final class AggregatedPracticeEntry {
  const AggregatedPracticeEntry({
    required this.id,
    required this.day,
    required this.source,
    required this.seconds,
    required this.strokes,
    required this.completion,
    required this.rhythm,
    required this.direction,
    required this.chord,
    required this.overall,
  });

  /// Session dedup identifier. For V2 sessions this is the
  /// [PracticeHistoryEntry.id] (the auth key for the V2 store); for V1
  /// entries it is the persisted-storage ordinal `v1-<index>` so a V1 entry
  /// can never share an id with a V2 entry (and the aggregator's dedup rule,
  /// A3, has nothing to do for V1).
  final String id;

  /// Epoch day (local-midnight) the practice happened on.
  final int day;

  /// Coarse mode bucket — reuses the V1 [PracticeSource] enum so the progress
  /// dashboard's source breakdown keeps the same shape (ADR 0085 Döntés 3).
  final PracticeSource source;

  /// Total practice seconds. For V2 entries this is `activeDuration.inSeconds`
  /// rounded down (the session's *active* time only — count-in, pause, and
  /// setup are excluded by the V2 controller). For V1 entries this is the
  /// stored `seconds` field, unchanged.
  final int seconds;

  /// Number of scored or recorded strums. For V2 this is the V2 entry's
  /// `attemptsCount` (the integer strike count, not the V2 `scorePoints`
  /// which is the running combo/score). For V1 entries this is the stored
  /// `strokes` field.
  final int strokes;

  final MetricValue completion;
  final MetricValue rhythm;
  final MetricValue direction;
  final MetricValue chord;
  final MetricValue overall;
}

/// Pure, deterministic union of the V1 `PracticeEntry` log and the V2
/// `PracticeHistoryEntry` store (ADR 0085 Döntés 1, brief A1–A3).
///
/// Built as a method that takes both source lists; no Riverpod, no clock, no
/// filesystem. The caller supplies the `today` epoch day for the day-split
/// queries so tests are deterministic.
@immutable
final class PracticeProgressAggregator {
  const PracticeProgressAggregator();

  /// Unify [v1] and [v2] into a single list of [AggregatedPracticeEntry].
  ///
  /// Dedup: identical [PracticeHistoryEntry.id] values inside [v2] collapse
  /// to a single record (the first occurrence wins — the V2 store already
  /// rejects duplicates on save, so a duplicate list here is a defensive
  /// guarantee). The V1 list contributes one record per V1 entry; V1 has no
  /// id field so V1 entries cannot overlap with V2 ids (A3).
  List<AggregatedPracticeEntry> aggregate({
    required Iterable<PracticeEntry> v1,
    required Iterable<PracticeHistoryEntry> v2,
  }) {
    final out = <AggregatedPracticeEntry>[];

    // V2 first → any V2 wins on id collisions and V1 follows with its own
    // synthesized v1-* id (no collision possible).
    final seenV2Ids = <String>{};
    for (final entry in v2) {
      if (!seenV2Ids.add(entry.id)) continue; // dedup (A3)
      out.add(_fromV2(entry));
    }

    var v1Ordinal = 0;
    for (final entry in v1) {
      v1Ordinal += 1;
      out.add(_fromV1(entry, ordinal: v1Ordinal));
    }

    return List.unmodifiable(out);
  }

  /// Number of distinct calendar days that hold at least one entry.
  int daysPracticed(List<AggregatedPracticeEntry> entries) =>
      entries.map((e) => e.day).toSet().length;

  /// Total practice seconds recorded on [day] (an epoch day). Drives the
  /// daily-goal ring.
  int secondsForDay(List<AggregatedPracticeEntry> entries, int day) => entries
      .where((e) => e.day == day)
      .fold<int>(0, (sum, e) => sum + (e.seconds < 0 ? 0 : e.seconds));

  /// How many sessions came in under [source].
  int sessionsFrom(
    List<AggregatedPracticeEntry> entries,
    PracticeSource source,
  ) => entries.where((e) => e.source == source).length;

  /// Average strum-direction accuracy across scored runs (0..1), or null when
  /// none scored yet. V2 records contribute their [direction] [MetricAvailable]
  /// value; V1 records contribute their `directionAccuracy` when non-null.
  double? averageDirectionAccuracy(List<AggregatedPracticeEntry> entries) {
    final scored = <double>[];
    for (final e in entries) {
      final dir = e.direction;
      if (dir is MetricAvailable) scored.add(dir.value);
    }
    if (scored.isEmpty) return null;
    final sum = scored.fold<double>(0, (s, v) => s + v);
    return sum / scored.length;
  }

  /// Best single scored strum-direction accuracy, or null when none.
  double? bestDirectionAccuracy(List<AggregatedPracticeEntry> entries) {
    double? best;
    for (final e in entries) {
      final dir = e.direction;
      if (dir is! MetricAvailable) continue;
      final v = dir.value;
      if (best == null || v > best) best = v;
    }
    return best;
  }

  // ---- Internal builders --------------------------------------------------

  AggregatedPracticeEntry _fromV1(PracticeEntry e, {required int ordinal}) {
    return AggregatedPracticeEntry(
      id: 'v1-$ordinal',
      day: e.day,
      source: e.source,
      seconds: e.seconds.clamp(0, 1 << 30),
      strokes: e.strokes.clamp(0, 1 << 30),
      // V1 has no rhythm / chord / completion / overall scores — they would
      // be guesses (ADR 0085 Döntés 2, A1).
      completion: const MetricNotApplicable(),
      rhythm: const MetricNotApplicable(),
      direction: e.directionAccuracy == null
          ? const MetricNotApplicable()
          : MetricAvailable(e.directionAccuracy!),
      chord: const MetricNotApplicable(),
      overall: const MetricNotApplicable(),
    );
  }

  AggregatedPracticeEntry _fromV2(PracticeHistoryEntry e) {
    return AggregatedPracticeEntry(
      id: e.id,
      day: _epochDayOf(e.createdAt),
      // V2 stores a stable .code; map it back to the V1 progress enum so
      // the dashboard's source breakdown keeps one shape (ADR 0085 Döntés 3).
      source: _progressSourceFromCode(e.sourceCode),
      // Only the ACTIVE time contributes (brief A5 — count-in, pause, setup,
      // result are excluded by the controller).
      seconds: e.activeDuration.inSeconds,
      // The V2 attempts count is the integer strike tally; the V2 scorePoints
      // is a points/weight value (not a stroke count) and is not used here.
      strokes: e.attemptsCount,
      completion: e.finalMetricSnapshot.completion.toMetricValue(),
      rhythm: e.finalMetricSnapshot.rhythm.toMetricValue(),
      direction: e.finalMetricSnapshot.direction.toMetricValue(),
      chord: e.finalMetricSnapshot.chord.toMetricValue(),
      overall: e.finalMetricSnapshot.overall.toMetricValue(),
    );
  }

  /// Maps the V2 stored `sourceCode` to the V1 dashboard enum. An unknown
  /// code never collapses to `live` here (that decision belongs to V1's own
  /// decoder) — instead the aggregator falls back to `live` as a stable,
  /// documented default and surfaces the V2 code via the `id`.
  static PracticeSource _progressSourceFromCode(String code) {
    switch (code) {
      case 'live':
        return PracticeSource.live;
      case 'analyze':
        return PracticeSource.analyze;
      case 'learn':
        return PracticeSource.learn;
      // Practice-domain codes that did not exist under the V1 enum get the
      // closest equivalent: `song`/`lesson` map to `learn` (curriculum
      // material), the rest map to `live` (the loose "ran the engine"
      // bucket). The fallback is never silent because the original V2 code
      // survives in `AggregatedPracticeEntry.id` and the history list.
      case 'builtin':
      case 'lesson':
      case 'song':
      case 'dailyChallenge':
      case 'setlist':
      case 'userCreated':
      case 'futureAi':
        // Practice-domain sources share the V1 `learn` bucket with the V2
        // `learn` mode and song-derived lessons. Treat free-standing ran
        // engine activity as live.
        if (code == 'lesson' || code == 'song' || code == 'builtin') {
          return PracticeSource.learn;
        }
        return PracticeSource.live;
      default:
        return PracticeSource.live;
    }
  }

  /// Local-midnight epoch day — mirrors [StreakLogic.epochDayOf] to keep the
  /// two domains aligned. Copied here (instead of importing) because the
  /// aggregator must stay free of cross-feature deps (ADR 0068 §4).
  static int _epochDayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
