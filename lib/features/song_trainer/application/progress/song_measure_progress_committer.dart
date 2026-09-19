// Per-measure progress commit for the Song Trainer.
//
// Javító sáv 2026-09-06, audit §5.2 "Dal-tréner ütemenkénti haladás-commit":
// the trainer finalised a session by committing ONE practice-history entry
// and nothing else, so [SongProgressRepository] stayed empty forever — and
// with it every measure/section projection [SongProgressAggregator] exists to
// compute (the result screen's "Song progress" card, the measure heatmap's
// historical side).
//
// This committer is the missing boundary: one durable [SongPracticeRecord]
// per measure of the finished attempt, keyed by the session's idempotency key
// so a replayed terminal tick cannot double-count a measure.
//
// It deliberately does NOT touch the daily goal, the streak, or the practice
// history — those are session-level facts owned by
// [SongProgressTerminalIntegrator] / [SongProgressCommitter]. Crediting them
// once per measure would inflate both.

import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_practice_record.dart';
import '../../domain/repositories/song_progress_repository.dart';
import '../trainer/song_trainer_result.dart';

/// Writes one [SongPracticeRecord] per measure of a finished attempt.
final class SongMeasureProgressCommitter {
  SongMeasureProgressCommitter({
    required this.repository,
    this.clock = DateTime.now,
  });

  final SongProgressRepository repository;
  final DateTime Function() clock;

  /// Record IDs already written by this committer instance. A terminal tick
  /// can be observed more than once; the repository is not required to be
  /// idempotent, so the guard lives here.
  final Set<String> _committed = <String>{};

  /// The stable measure identity a Song Trainer record is addressed by.
  ///
  /// A [SongMeasure] carries an index, not a string id, so the progress
  /// coordinate is derived from the index deterministically. The revision
  /// mapper ([SongRevisionProgressMapper]) only ever compares these strings,
  /// never parses them.
  static String measureIdFor(int measureIndex) => 'measure-$measureIndex';

  /// Persists every measure of [result].
  ///
  /// Returns the number of records actually written. The first repository
  /// failure aborts and is returned as-is — a swallowed write here would look
  /// like recorded progress the user never gets back.
  Future<AppResult<int>> commit({
    required String attemptKey,
    required SongTrainerResult result,
    required Duration activeDuration,
  }) async {
    final total = result.verdicts.length;
    if (total == 0) return const Success<int>(0);
    final recordedAt = clock();
    final elapsed = activeDuration.isNegative ? Duration.zero : activeDuration;
    var written = 0;
    for (final measure in result.measureResults) {
      final id = '$attemptKey|measure|${measure.measureIndex}';
      if (!_committed.add(id)) continue;
      final record = _recordFor(
        id: id,
        measure: measure,
        total: total,
        activeDuration: elapsed,
        recordedAt: recordedAt,
      );
      if (record == null) {
        _committed.remove(id);
        continue;
      }
      final saved = await repository.save(record);
      if (saved case Failure(:final error)) {
        _committed.remove(id);
        return Failure<int>(error);
      }
      written++;
    }
    return Success<int>(written);
  }

  static SongPracticeRecord? _recordFor({
    required String id,
    required SongMeasureTrainerResult measure,
    required int total,
    required Duration activeDuration,
    required DateTime recordedAt,
  }) {
    final verdicts = measure.verdicts;
    if (verdicts.isEmpty) return null;
    final reference = verdicts.first.reference;
    // The measure's share of the attempt's active time, weighted by how many
    // of its target events the measure owns. The shares sum back to the
    // session total (modulo integer truncation), so no minute is invented.
    final micros = activeDuration.inMicroseconds * verdicts.length ~/ total;
    var score = measure.averageEventScore;
    if (!score.isFinite || score < 0) score = 0;
    if (score > 1) score = 1;
    return SongPracticeRecord(
      id: id,
      songId: reference.songId,
      songRevision: reference.songRevision,
      source: SongProgressSource(
        measureId: measureIdFor(measure.measureIndex),
        eventId: reference.eventId.value,
        measureIndex: measure.measureIndex,
        sectionId: reference.sectionId?.value,
      ),
      activeDuration: Duration(microseconds: micros),
      completed: verdicts.where(_isMissed).isEmpty,
      score: score,
      recordedAt: recordedAt,
    );
  }

  static bool _isMissed(SongTrainerVerdict entry) =>
      entry.verdict.missReasonCode != null;
}
