import 'package:meta/meta.dart';

enum NotePitchGrade { exact, near, offPitch, wrongNote, noStablePitch }

enum NoteOnsetGrade { early, onTime, late, missed }

/// A resolved sounding-pitch target passed to the scorer.
@immutable
final class NoteScoringTarget {
  const NoteScoringTarget({
    required this.id,
    required this.midiPitch,
    required this.start,
    required this.duration,
  });

  final String id;
  final int midiPitch;
  final Duration start;
  final Duration duration;

  Duration get end => start + duration;
}

/// Thresholds for deterministic note scoring.
@immutable
final class NoteScoringPolicy {
  const NoteScoringPolicy({
    this.exactCents = 12,
    this.nearCents = 35,
    this.offPitchCents = 70,
    this.earlyOnsetTolerance = const Duration(milliseconds: 80),
    this.lateOnsetTolerance = const Duration(milliseconds: 80),
    this.targetMatchTolerance = const Duration(milliseconds: 150),
    this.minimumCoverage = 0.6,
    this.inputLatency = const Duration(milliseconds: 80),
    this.coverageFrameHold = const Duration(milliseconds: 60),
    this.minimumRms = 0.014,
    this.minimumClarity = 0.85,
  });

  final double exactCents;
  final double nearCents;
  final double offPitchCents;
  final Duration earlyOnsetTolerance;
  final Duration lateOnsetTolerance;
  final Duration targetMatchTolerance;
  final double minimumCoverage;
  final Duration inputLatency;
  final Duration coverageFrameHold;
  final double minimumRms;
  final double minimumClarity;
}

@immutable
final class NoteScoringNoteUpdate {
  const NoteScoringNoteUpdate({
    required this.targetId,
    required this.pitchGrade,
    required this.onsetGrade,
  });

  final String targetId;
  final NotePitchGrade pitchGrade;
  final NoteOnsetGrade onsetGrade;
}

@immutable
final class NoteScoringUpdate {
  const NoteScoringUpdate({
    required this.compensatedAt,
    this.noteUpdates = const <NoteScoringNoteUpdate>[],
    this.extraNoteDetected = false,
  });

  final Duration compensatedAt;
  final List<NoteScoringNoteUpdate> noteUpdates;
  final bool extraNoteDetected;
}

@immutable
final class NoteScoringNoteResult {
  const NoteScoringNoteResult({
    required this.targetId,
    required this.pitchGrade,
    required this.onsetGrade,
    required this.coverage,
  });

  final String targetId;
  final NotePitchGrade pitchGrade;
  final NoteOnsetGrade onsetGrade;
  final double coverage;

  @override
  bool operator ==(Object other) =>
      other is NoteScoringNoteResult &&
      other.targetId == targetId &&
      other.pitchGrade == pitchGrade &&
      other.onsetGrade == onsetGrade &&
      other.coverage == coverage;

  @override
  int get hashCode => Object.hash(targetId, pitchGrade, onsetGrade, coverage);
}

@immutable
final class NoteScoringResult {
  const NoteScoringResult({required this.notes, required this.extraNoteCount});

  final List<NoteScoringNoteResult> notes;
  final int extraNoteCount;

  @override
  bool operator ==(Object other) {
    if (other is! NoteScoringResult ||
        other.extraNoteCount != extraNoteCount ||
        other.notes.length != notes.length) {
      return false;
    }
    for (var index = 0; index < notes.length; index++) {
      if (notes[index] != other.notes[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(extraNoteCount, Object.hashAll(notes));
}
