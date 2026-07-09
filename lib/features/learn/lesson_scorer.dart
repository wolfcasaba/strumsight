import '../live/model/strum.dart';
import 'model/lesson.dart';

/// How a single lesson event resolved.
enum HitResult { hit, wrongDirection, missed }

/// Immutable snapshot of a scoring run (for the UI + tests).
class ScoreSnapshot {
  const ScoreSnapshot({
    required this.hits,
    required this.wrong,
    required this.missed,
    required this.combo,
    required this.maxCombo,
    required this.total,
    required this.lastResult,
    this.chordHits = 0,
    this.chordTotal = 0,
  });

  final int hits;
  final int wrong;
  final int missed;
  final int combo;
  final int maxCombo;
  final int total;
  final HitResult? lastResult;

  /// Chord-correctness (secondary): events (with a chord) where the right chord
  /// was sounding around the stroke. Lag-tolerant, never gates the strum hit.
  final int chordHits;
  final int chordTotal;

  int get resolved => hits + wrong + missed;
  bool get finished => resolved >= total;

  /// Fraction of events struck with the correct direction in time.
  double get accuracy => total == 0 ? 0 : hits / total;

  bool get hasChords => chordTotal > 0;
  double get chordAccuracy => chordTotal == 0 ? 0 : chordHits / chordTotal;
}

/// Pure scorer for a play-along run: matches the player's detected strums
/// (direction + time) to the lesson's timed events and tallies hits, wrong
/// directions, misses and a combo (RAG chunk 014). No clocks/IO — the screen
/// feeds it detected strums + a monotically advancing elapsed time, so the whole
/// thing is deterministically testable.
class LessonScorer {
  LessonScorer(
    Lesson lesson, {
    this.countInBeats = 4,
    this.windowSec = 0.28,
  }) : _secPerBeat = 60.0 / lesson.bpm {
    for (final e in lesson.events) {
      final t = (countInBeats + e.beat) * _secPerBeat;
      _events.add(_Timed(e, t));
      if (e.chord.isNotEmpty) _chordSlots.add(_ChordSlot(e.chord, t));
    }
    total = _events.length;
    chordTotal = _chordSlots.length;
  }

  /// Timing tolerance for a strum to count for an event (±).
  final double windowSec;
  final int countInBeats;
  final double _secPerBeat;

  final List<_Timed> _events = [];
  final List<_ChordSlot> _chordSlots = [];
  final List<_Obs> _chordObs = []; // detected-chord change-points

  /// How far AFTER a stroke we still credit its chord (chord detection lags the
  /// strum onset by ~1 analysis window).
  static const double _chordLagSec = 0.37;

  int total = 0;
  int hits = 0;
  int wrong = 0;
  int missed = 0;
  int combo = 0;
  int maxCombo = 0;
  HitResult? lastResult;

  int chordTotal = 0;
  int chordHits = 0;
  int chordMiss = 0;

  /// Pass mark (share of events hit correctly).
  static const double passThreshold = 0.7;

  int get resolved => hits + wrong + missed;
  bool get finished => resolved >= total;
  double get accuracy => total == 0 ? 0 : hits / total;
  bool get passed => total > 0 && accuracy >= passThreshold;

  ScoreSnapshot snapshot() => ScoreSnapshot(
        hits: hits,
        wrong: wrong,
        missed: missed,
        combo: combo,
        maxCombo: maxCombo,
        total: total,
        lastResult: lastResult,
        chordHits: chordHits,
        chordTotal: chordTotal,
      );

  /// Record the currently detected chord [label] ('' = none) at [elapsedSec].
  /// Only change-points are kept; used to grade chord-correctness leniently.
  void observeChord(String label, double elapsedSec) {
    if (_chordObs.isEmpty || _chordObs.last.label != label) {
      _chordObs.add(_Obs(elapsedSec, label));
    }
  }

  /// The detected chord active at time [t] (the last change-point at or before
  /// t), or '' if none observed yet.
  String _chordAt(double t) {
    var label = '';
    for (final o in _chordObs) {
      if (o.time <= t) {
        label = o.label;
      } else {
        break;
      }
    }
    return label;
  }

  /// Evaluate any chord slot whose lag window has fully passed [elapsedSec].
  void _evalChords(double elapsedSec) {
    for (final s in _chordSlots) {
      if (s.evaluated) continue;
      if (s.time + _chordLagSec + windowSec >= elapsedSec) continue;
      s.evaluated = true;
      // Correct if the target chord was sounding at the stroke, or shortly
      // after (allowing for chord-detection lag).
      final ok = _chordAt(s.time) == s.chord ||
          _chordAt(s.time + _chordLagSec) == s.chord;
      if (ok) {
        chordHits++;
      } else {
        chordMiss++;
      }
    }
  }

  /// The absolute elapsed time (seconds from lesson start, count-in included)
  /// at which [event] should be struck — handy for UI hit flashes.
  double timeOf(LessonEvent event) =>
      (countInBeats + event.beat) * _secPerBeat;

  /// Register a detected strum at [elapsedSec]; matches it to the nearest
  /// still-open event within [windowSec]. A strum with no event in range is an
  /// extra (ignored — we don't punish enthusiasm here).
  void registerStrum(StrumDirection dir, double elapsedSec) {
    _Timed? best;
    var bestDelta = windowSec + 1e9;
    for (final t in _events) {
      if (t.matched) continue;
      final d = (t.time - elapsedSec).abs();
      if (d <= windowSec && d < bestDelta) {
        best = t;
        bestDelta = d;
      }
    }
    if (best == null) return; // extra strum, no open event nearby
    best.matched = true;
    if (dir == best.event.direction) {
      hits++;
      combo++;
      if (combo > maxCombo) maxCombo = combo;
      lastResult = HitResult.hit;
    } else {
      wrong++;
      combo = 0;
      lastResult = HitResult.wrongDirection;
    }
  }

  /// Advance the clock to [elapsedSec]; any open event whose window has fully
  /// passed is a miss, and any chord slot past its lag window is graded.
  void advance(double elapsedSec) {
    for (final t in _events) {
      if (t.matched) continue;
      if (t.time + windowSec < elapsedSec) {
        t.matched = true;
        missed++;
        combo = 0;
        lastResult = HitResult.missed;
      }
    }
    _evalChords(elapsedSec);
  }

  /// Resolve any still-open events as misses + grade all chords (lesson end).
  void finalize() {
    for (final t in _events) {
      if (!t.matched) {
        t.matched = true;
        missed++;
      }
    }
    _evalChords(double.infinity);
  }
}

class _ChordSlot {
  _ChordSlot(this.chord, this.time);
  final String chord;
  final double time;
  bool evaluated = false;
}

class _Obs {
  _Obs(this.time, this.label);
  final double time;
  final String label;
}

class _Timed {
  _Timed(this.event, this.time);
  final LessonEvent event;
  final double time;
  bool matched = false;
}
