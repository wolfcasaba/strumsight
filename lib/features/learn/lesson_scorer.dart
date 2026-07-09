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
  });

  final int hits;
  final int wrong;
  final int missed;
  final int combo;
  final int maxCombo;
  final int total;
  final HitResult? lastResult;

  int get resolved => hits + wrong + missed;
  bool get finished => resolved >= total;

  /// Fraction of events struck with the correct direction in time.
  double get accuracy => total == 0 ? 0 : hits / total;
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
      _events.add(_Timed(e, (countInBeats + e.beat) * _secPerBeat));
    }
    total = _events.length;
  }

  /// Timing tolerance for a strum to count for an event (±).
  final double windowSec;
  final int countInBeats;
  final double _secPerBeat;

  final List<_Timed> _events = [];

  int total = 0;
  int hits = 0;
  int wrong = 0;
  int missed = 0;
  int combo = 0;
  int maxCombo = 0;
  HitResult? lastResult;

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
      );

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
  /// passed is a miss.
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
  }

  /// Resolve any still-open events as misses (call at lesson end).
  void finalize() {
    for (final t in _events) {
      if (!t.matched) {
        t.matched = true;
        missed++;
      }
    }
  }
}

class _Timed {
  _Timed(this.event, this.time);
  final LessonEvent event;
  final double time;
  bool matched = false;
}
