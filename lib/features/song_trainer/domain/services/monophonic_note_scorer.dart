import 'package:strumsight/core/audio/pitch/pitch_observation.dart';

import '../models/note_scoring_models.dart';

/// Deterministic scorer for a single resolved pitch-target sequence.
final class MonophonicNoteScorer {
  MonophonicNoteScorer({
    required this.startedAt,
    required List<NoteScoringTarget> targets,
    this.policy = const NoteScoringPolicy(),
  }) : _targets = List<NoteScoringTarget>.unmodifiable(targets),
       _scores = <String, _TargetScore>{
         for (final target in targets) target.id: _TargetScore(target),
       };

  final DateTime startedAt;
  final NoteScoringPolicy policy;
  final List<NoteScoringTarget> _targets;
  final Map<String, _TargetScore> _scores;
  bool _outsideStablePitch = false;
  int _extraNoteCount = 0;

  NoteScoringUpdate observe(PitchObservation observation) {
    final compensatedAt =
        observation.observedAt.difference(startedAt) - policy.inputLatency;
    final trusted = _isTrusted(observation);
    final target = _targetAt(compensatedAt);
    if (target == null) {
      final extraOnset = trusted && !_outsideStablePitch;
      if (extraOnset) _extraNoteCount++;
      _outsideStablePitch = trusted;
      return NoteScoringUpdate(
        compensatedAt: compensatedAt,
        extraNoteDetected: extraOnset,
      );
    }
    _outsideStablePitch = false;
    final score = _scores[target.id]!;
    if (!trusted) {
      return NoteScoringUpdate(
        compensatedAt: compensatedAt,
        noteUpdates: <NoteScoringNoteUpdate>[score.update],
      );
    }
    final pitchGrade = _pitchGrade(target, observation);
    score.observe(
      at: compensatedAt,
      pitchGrade: pitchGrade,
      onsetGrade: _onsetGrade(target, compensatedAt),
      policy: policy,
    );
    return NoteScoringUpdate(
      compensatedAt: compensatedAt,
      noteUpdates: <NoteScoringNoteUpdate>[score.update],
    );
  }

  NoteScoringUpdate advance(Duration activeTime) {
    final completed = <NoteScoringNoteUpdate>[];
    for (final target in _targets) {
      final score = _scores[target.id]!;
      if (score.isFinalized ||
          activeTime <= target.end + policy.lateOnsetTolerance) {
        continue;
      }
      score.finalize();
      completed.add(score.update);
    }
    return NoteScoringUpdate(
      compensatedAt: activeTime,
      noteUpdates: List<NoteScoringNoteUpdate>.unmodifiable(completed),
    );
  }

  NoteScoringResult finalize() {
    for (final score in _scores.values) {
      score.finalize();
    }
    return NoteScoringResult(
      notes: List<NoteScoringNoteResult>.unmodifiable([
        for (final target in _targets) _scores[target.id]!.result,
      ]),
      extraNoteCount: _extraNoteCount,
    );
  }

  NoteScoringTarget? _targetAt(Duration at) {
    for (final target in _targets) {
      final score = _scores[target.id]!;
      final opensAt = target.start - policy.targetMatchTolerance;
      final closesAt = target.end + policy.targetMatchTolerance;
      if (!score.isFinalized && at >= opensAt && at <= closesAt) {
        return target;
      }
    }
    return null;
  }

  NotePitchGrade _pitchGrade(
    NoteScoringTarget target,
    PitchObservation observation,
  ) {
    final cents =
        ((observation.midiPitch - target.midiPitch) * 100 +
                observation.centsFromNearest)
            .abs();
    if (cents <= policy.exactCents) return NotePitchGrade.exact;
    if (cents <= policy.nearCents) return NotePitchGrade.near;
    if (cents <= policy.offPitchCents) return NotePitchGrade.offPitch;
    return NotePitchGrade.wrongNote;
  }

  bool _isTrusted(PitchObservation observation) =>
      observation.stable &&
      observation.frequencyHz.isFinite &&
      observation.clarity.isFinite &&
      observation.clarity >= policy.minimumClarity &&
      observation.rms.isFinite &&
      observation.rms >= policy.minimumRms;

  NoteOnsetGrade _onsetGrade(NoteScoringTarget target, Duration at) {
    final error = at - target.start;
    if (error < -policy.earlyOnsetTolerance) return NoteOnsetGrade.early;
    if (error > policy.lateOnsetTolerance) return NoteOnsetGrade.late;
    return NoteOnsetGrade.onTime;
  }
}

final class _TargetScore {
  _TargetScore(this.target);

  final NoteScoringTarget target;
  final List<_CoverageInterval> _coverageIntervals = <_CoverageInterval>[];
  NotePitchGrade _pitchGrade = NotePitchGrade.noStablePitch;
  NoteOnsetGrade _onsetGrade = NoteOnsetGrade.missed;
  bool isFinalized = false;

  NoteScoringNoteUpdate get update => NoteScoringNoteUpdate(
    targetId: target.id,
    pitchGrade: _pitchGrade,
    onsetGrade: _onsetGrade,
  );

  NoteScoringNoteResult get result => NoteScoringNoteResult(
    targetId: target.id,
    pitchGrade: _pitchGrade,
    onsetGrade: _onsetGrade,
    coverage: _coverage,
  );

  void observe({
    required Duration at,
    required NotePitchGrade pitchGrade,
    required NoteOnsetGrade onsetGrade,
    required NoteScoringPolicy policy,
  }) {
    if (_pitchRank(pitchGrade) < _pitchRank(_pitchGrade)) {
      _pitchGrade = pitchGrade;
    }
    if (_onsetGrade == NoteOnsetGrade.missed) {
      _onsetGrade = onsetGrade;
    }
    if (_countsAsCorrect(pitchGrade)) {
      _addCoverage(at, policy.coverageFrameHold);
    }
  }

  void finalize() {
    isFinalized = true;
  }

  void _addCoverage(Duration at, Duration hold) {
    final start = at < target.start ? target.start : at;
    final end = at + hold > target.end ? target.end : at + hold;
    if (end <= start) return;
    _coverageIntervals.add(_CoverageInterval(start: start, end: end));
    _coverageIntervals.sort((a, b) => a.start.compareTo(b.start));
    final merged = <_CoverageInterval>[];
    for (final interval in _coverageIntervals) {
      if (merged.isEmpty || interval.start > merged.last.end) {
        merged.add(interval);
      } else if (interval.end > merged.last.end) {
        merged[merged.length - 1] = _CoverageInterval(
          start: merged.last.start,
          end: interval.end,
        );
      }
    }
    _coverageIntervals
      ..clear()
      ..addAll(merged);
  }

  double get _coverage {
    final covered = _coverageIntervals.fold<int>(
      0,
      (sum, interval) => sum + (interval.end - interval.start).inMicroseconds,
    );
    return covered / target.duration.inMicroseconds;
  }

  static bool _countsAsCorrect(NotePitchGrade grade) =>
      grade == NotePitchGrade.exact || grade == NotePitchGrade.near;

  static int _pitchRank(NotePitchGrade grade) => switch (grade) {
    NotePitchGrade.exact => 0,
    NotePitchGrade.near => 1,
    NotePitchGrade.offPitch => 2,
    NotePitchGrade.wrongNote => 3,
    NotePitchGrade.noStablePitch => 4,
  };
}

final class _CoverageInterval {
  const _CoverageInterval({required this.start, required this.end});

  final Duration start;
  final Duration end;
}
