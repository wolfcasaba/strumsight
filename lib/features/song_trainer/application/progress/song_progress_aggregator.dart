import 'dart:async';

import 'package:strumsight/features/practice/public.dart';

import '../../domain/models/song_id.dart';
import '../../domain/models/song_practice_record.dart';
import '../../domain/repositories/song_progress_repository.dart';
import '../trainer/song_progress_committer.dart';

const int _secondsPerMinute = 60;

/// Deterministic measure and section projections of persisted song records.
final class SongProgressAggregator {
  const SongProgressAggregator._();

  static SongProgressAggregate aggregate(List<SongPracticeRecord> input) {
    final unique = <String, SongPracticeRecord>{};
    for (final record in input) {
      unique.putIfAbsent(record.id, () => record);
    }
    final records = unique.values.where((record) => !record.isArchived).toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    if (records.isEmpty) return const SongProgressAggregate.empty();
    final songId = records.first.songId;
    final revision = records.first.songRevision;
    if (records.any(
      (record) => record.songId != songId || record.songRevision != revision,
    )) {
      throw ArgumentError('An aggregate requires one song revision.');
    }
    final byMeasure = <String, List<SongPracticeRecord>>{};
    final bySection = <String?, List<SongPracticeRecord>>{};
    for (final record in records) {
      byMeasure
          .putIfAbsent(record.source.measureId, () => <SongPracticeRecord>[])
          .add(record);
      bySection
          .putIfAbsent(record.source.sectionId, () => <SongPracticeRecord>[])
          .add(record);
    }
    final measures =
        byMeasure.entries.map((entry) {
          final source = entry.value.first.source;
          return SongMeasureProgress.fromRecords(
            measureId: entry.key,
            measureIndex: source.measureIndex,
            records: entry.value,
          );
        }).toList()..sort((left, right) {
          final byIndex = left.measureIndex.compareTo(right.measureIndex);
          return byIndex != 0
              ? byIndex
              : left.measureId.compareTo(right.measureId);
        });
    final sections =
        bySection.entries
            .map(
              (entry) => SongSectionProgress.fromRecords(
                sectionId: entry.key,
                records: entry.value,
              ),
            )
            .toList()
          ..sort(
            (left, right) =>
                (left.sectionId ?? '').compareTo(right.sectionId ?? ''),
          );
    return SongProgressAggregate(
      songId: songId,
      songRevision: revision,
      measures: measures,
      sections: sections,
    );
  }
}

final class SongMeasureProgress {
  SongMeasureProgress.fromRecords({
    required this.measureId,
    required this.measureIndex,
    required List<SongPracticeRecord> records,
  }) : attempts = records.length,
       completions = records.where((record) => record.completed).length,
       bestScore = records.map((record) => record.score).reduce(_max),
       averageScore = _average(records),
       activeDuration = _totalDuration(records);

  final String measureId;
  final int measureIndex;
  final int attempts;
  final int completions;
  final double bestScore;
  final double averageScore;
  final Duration activeDuration;

  @override
  bool operator ==(Object other) =>
      other is SongMeasureProgress &&
      other.measureId == measureId &&
      other.measureIndex == measureIndex &&
      other.attempts == attempts &&
      other.completions == completions &&
      other.bestScore == bestScore &&
      other.averageScore == averageScore &&
      other.activeDuration == activeDuration;

  @override
  int get hashCode => Object.hash(
    measureId,
    measureIndex,
    attempts,
    completions,
    bestScore,
    averageScore,
    activeDuration,
  );
}

final class SongSectionProgress {
  SongSectionProgress.fromRecords({
    required this.sectionId,
    required List<SongPracticeRecord> records,
  }) : attempts = records.length,
       completions = records.where((record) => record.completed).length,
       averageScore = _average(records),
       activeDuration = _totalDuration(records);

  final String? sectionId;
  final int attempts;
  final int completions;
  final double averageScore;
  final Duration activeDuration;

  @override
  bool operator ==(Object other) =>
      other is SongSectionProgress &&
      other.sectionId == sectionId &&
      other.attempts == attempts &&
      other.completions == completions &&
      other.averageScore == averageScore &&
      other.activeDuration == activeDuration;

  @override
  int get hashCode => Object.hash(
    sectionId,
    attempts,
    completions,
    averageScore,
    activeDuration,
  );
}

final class SongProgressAggregate {
  const SongProgressAggregate.empty()
    : songId = null,
      songRevision = null,
      measures = const <SongMeasureProgress>[],
      sections = const <SongSectionProgress>[];

  SongProgressAggregate({
    required this.songId,
    required this.songRevision,
    required List<SongMeasureProgress> measures,
    required List<SongSectionProgress> sections,
  }) : measures = List<SongMeasureProgress>.unmodifiable(measures),
       sections = List<SongSectionProgress>.unmodifiable(sections);

  final SongId? songId;
  final int? songRevision;
  final List<SongMeasureProgress> measures;
  final List<SongSectionProgress> sections;

  @override
  bool operator ==(Object other) =>
      other is SongProgressAggregate &&
      other.songId == songId &&
      other.songRevision == songRevision &&
      _sameList(other.measures, measures) &&
      _sameList(other.sections, sections);

  @override
  int get hashCode => Object.hash(
    songId,
    songRevision,
    Object.hashAll(measures),
    Object.hashAll(sections),
  );
}

/// Publicly injectable daily-goal/streak recording boundary for song progress.
abstract interface class SongPracticeCreditRecorder {
  Future<SongPracticeCreditOutcome> record(SongPracticeRecord record);
}

final class SongPracticeCreditOutcome {
  const SongPracticeCreditOutcome({
    required this.streakCredited,
    required this.dailyGoalActiveSeconds,
  });

  final bool streakCredited;
  final int dailyGoalActiveSeconds;
}

/// Bridges a scored Song Trainer result into the public Practice recording use case.
final class PracticeSessionSongCreditRecorder
    implements SongPracticeCreditRecorder {
  const PracticeSessionSongCreditRecorder({
    required PracticeSessionRecording recording,
    required int dailyGoalMinutes,
  }) : this._(recording, dailyGoalMinutes);

  const PracticeSessionSongCreditRecorder._(
    this._recording,
    this.dailyGoalMinutes,
  );

  final PracticeSessionRecording _recording;
  final int dailyGoalMinutes;

  int get dailyGoalTargetSeconds => _secondsPerMinute * dailyGoalMinutes;

  @override
  Future<SongPracticeCreditOutcome> record(SongPracticeRecord record) async {
    if (record.playbackOnly) {
      return const SongPracticeCreditOutcome(
        streakCredited: false,
        dailyGoalActiveSeconds: 0,
      );
    }
    final outcome = await _recording.record(
      PracticeRecordingRequest(
        lessonId: 'song-${record.songId.value}',
        eligibility: SessionEligibilitySnapshot(
          activeDuration: record.activeDuration,
          resolvedRequiredTargets: record.completed ? 1 : 0,
          freePracticeStrums: 0,
        ),
        eligible: record.completed,
        activeDuration: record.activeDuration,
        elapsedSeconds: record.activeDuration.inSeconds,
        strokes: record.completed ? 1 : 0,
        chords: 0,
        directionAccuracy: null,
        finishedAt: record.recordedAt,
      ),
    );
    return SongPracticeCreditOutcome(
      streakCredited: outcome.streakAdvanced,
      dailyGoalActiveSeconds: outcome.addedActiveSeconds,
    );
  }
}

/// Exactly-once route-local terminal fan-out for record, history, daily goal and streak.
final class SongProgressTerminalIntegrator {
  SongProgressTerminalIntegrator({
    required SongProgressRepository progressRepository,
    required SongProgressCommitter historyCommitter,
    required SongPracticeCreditRecorder creditRecorder,
  }) : this._(progressRepository, historyCommitter, creditRecorder);

  SongProgressTerminalIntegrator._(
    this._progressRepository,
    this._historyCommitter,
    this._creditRecorder,
  );

  final SongProgressRepository _progressRepository;
  final SongProgressCommitter _historyCommitter;
  final SongPracticeCreditRecorder _creditRecorder;
  final Map<String, Future<SongProgressTerminalCommitOutcome>> _commits =
      <String, Future<SongProgressTerminalCommitOutcome>>{};

  Future<SongProgressTerminalCommitOutcome> commit({
    required String idempotencyKey,
    required SongPracticeRecord record,
    required PracticeSessionResult sessionResult,
  }) {
    final existing = _commits[idempotencyKey];
    if (existing != null) return existing;
    final pending = _commit(
      idempotencyKey: idempotencyKey,
      record: record,
      sessionResult: sessionResult,
    );
    _commits[idempotencyKey] = pending;
    unawaited(
      pending.then((outcome) {
        if (!outcome.isSuccess) _commits.remove(idempotencyKey);
      }),
    );
    return pending;
  }

  Future<SongProgressTerminalCommitOutcome> _commit({
    required String idempotencyKey,
    required SongPracticeRecord record,
    required PracticeSessionResult sessionResult,
  }) async {
    final history = await _historyCommitter.commit(
      idempotencyKey: idempotencyKey,
      sessionResult: sessionResult,
    );
    if (history.isFailure) {
      return const SongProgressTerminalCommitOutcome.failure();
    }
    final persisted = await _progressRepository.save(record);
    if (persisted.isFailure) {
      return const SongProgressTerminalCommitOutcome.failure();
    }
    final credit = await _creditRecorder.record(record);
    return SongProgressTerminalCommitOutcome.success(credit: credit);
  }
}

final class SongProgressTerminalCommitOutcome {
  const SongProgressTerminalCommitOutcome.success({required this.credit})
    : isSuccess = true;
  const SongProgressTerminalCommitOutcome.failure()
    : isSuccess = false,
      credit = null;

  final bool isSuccess;
  final SongPracticeCreditOutcome? credit;
}

double _max(double left, double right) => left > right ? left : right;
double _average(List<SongPracticeRecord> records) =>
    records.fold<double>(0, (sum, record) => sum + record.score) /
    records.length;
Duration _totalDuration(List<SongPracticeRecord> records) =>
    records.fold<Duration>(
      Duration.zero,
      (total, record) => total + record.activeDuration,
    );
bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
