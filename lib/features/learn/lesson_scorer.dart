import '../live/model/strum.dart';
import 'model/lesson.dart';

/// How a single lesson event resolved.
enum HitResult { hit, wrongDirection, missed }

/// Timing quality of a correct-direction hit (game-feel / juice, chunk 016b).
/// Rhythm-game convention: a tight window is PERFECT, a looser one GOOD, and
/// anything still inside the hit window but off-centre is EARLY (struck before
/// the beat) or LATE (after). Only meaningful when [HitResult.hit].
enum Timing { perfect, good, early, late }

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
    this.score = 0,
    this.multiplier = 1,
    this.perfect = 0,
    this.lastTiming,
    this.expectedDirection,
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

  /// Running points (perfect/good/off-beat hits × the combo multiplier).
  final int score;

  /// Current combo multiplier (×1/×2/×3/×4) — the reward chain.
  final int multiplier;

  /// How many hits landed in the tight PERFECT window (for the summary/brag).
  final int perfect;

  /// Timing quality of the most recent hit (null if the last event wasn't a
  /// correct-direction hit).
  final Timing? lastTiming;

  /// On a wrong-direction verdict: the direction the event WANTED (016b P6).
  final StrumDirection? expectedDirection;

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
    this.perfectWindowSec = 0.05,
    this.goodWindowSec = 0.12,
    this.inputLatencySec = 0,
    double? bpm,
  }) : _secPerBeat = 60.0 / (bpm ?? lesson.bpm) {
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

  /// Calibrated mic→detection latency (chunk 016b P3): a strum DETECTED at
  /// `t` was PLAYED at `t − inputLatencySec`. Every mic-fed timestamp
  /// (strums, chord observations, the miss-closing clock) is corrected by
  /// this before matching, so an on-beat player is graded on-beat regardless
  /// of the device's audio path. From the Settings tap-test; 0 = uncalibrated.
  final double inputLatencySec;

  /// Tight window (±) for a PERFECT hit; the next tier is GOOD.
  final double perfectWindowSec;
  final double goodWindowSec;
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

  int score = 0;
  int perfectHits = 0;
  Timing? lastTiming;

  /// On a wrong-direction hit: the direction the event WANTED (016b P6 —
  /// the badge tells the player which way the stroke should have gone).
  /// Null on any other verdict so the coaching never goes stale.
  StrumDirection? lastExpectedDirection;

  /// Base points per hit by timing tier (before the combo multiplier).
  static const _pointsPerfect = 100;
  static const _pointsGood = 70;
  static const _pointsOffBeat = 40;

  /// Combo multiplier (the reward chain): ×1 → ×2 (5) → ×3 (10) → ×4 (20).
  int get multiplier => combo >= 20
      ? 4
      : combo >= 10
          ? 3
          : combo >= 5
              ? 2
              : 1;

  int chordTotal = 0;
  int chordHits = 0;
  int chordMiss = 0;

  /// Dynamic-difficulty signal (016b P4, r154): consecutive failed events
  /// (miss or wrong-direction) since the last clean hit.
  int failStreak = 0;

  /// After this many consecutive failures the screen OFFERS the Easy cut
  /// (never forces it — the player stays in charge).
  static const int suggestEasyAfter = 4;
  bool get suggestsEasier => failStreak >= suggestEasyAfter;

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
        score: score,
        multiplier: multiplier,
        perfect: perfectHits,
        lastTiming: lastTiming,
        expectedDirection: lastExpectedDirection,
        chordHits: chordHits,
        chordTotal: chordTotal,
      );

  /// Timing tier for a hit landed [offsetSec] from the target (signed:
  /// negative = early, positive = late).
  Timing _timingFor(double offsetSec) {
    final mag = offsetSec.abs();
    if (mag <= perfectWindowSec) return Timing.perfect;
    if (mag <= goodWindowSec) return Timing.good;
    return offsetSec < 0 ? Timing.early : Timing.late;
  }

  /// Record the currently detected chord [label] ('' = none) at [elapsedSec].
  /// Only change-points are kept; used to grade chord-correctness leniently.
  void observeChord(String label, double elapsedSec) {
    final t = elapsedSec - inputLatencySec;
    if (_chordObs.isEmpty || _chordObs.last.label != label) {
      _chordObs.add(_Obs(t, label));
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
  /// extra (ignored — we don't punish enthusiasm here). Returns how it
  /// resolved ([HitResult.hit]/[HitResult.wrongDirection]) or null if it
  /// matched no open event (so the caller doesn't fire a stale-verdict haptic).
  HitResult? registerStrum(StrumDirection dir, double elapsedSec) {
    // Correct the detection timestamp back to when the strum was PLAYED.
    final playedSec = elapsedSec - inputLatencySec;
    _Timed? best;
    var bestDelta = windowSec + 1e9;
    for (final t in _events) {
      if (t.matched) continue;
      final d = (t.time - playedSec).abs();
      if (d <= windowSec && d < bestDelta) {
        best = t;
        bestDelta = d;
      }
    }
    if (best == null) return null; // extra strum, no open event nearby
    best.matched = true;
    if (dir == best.event.direction) {
      hits++;
      failStreak = 0;
      combo++;
      if (combo > maxCombo) maxCombo = combo;
      lastResult = HitResult.hit;
      // Timing tier + points × the (now-updated) combo multiplier.
      final timing = _timingFor(playedSec - best.time);
      lastTiming = timing;
      if (timing == Timing.perfect) perfectHits++;
      lastExpectedDirection = null;
      final base = switch (timing) {
        Timing.perfect => _pointsPerfect,
        Timing.good => _pointsGood,
        Timing.early || Timing.late => _pointsOffBeat,
      };
      score += base * multiplier;
      return HitResult.hit;
    } else {
      wrong++;
      failStreak++;
      combo = 0;
      lastResult = HitResult.wrongDirection;
      lastTiming = null;
      lastExpectedDirection = best.event.direction;
      return HitResult.wrongDirection;
    }
  }

  /// Advance the clock to [elapsedSec]; any open event whose window has fully
  /// passed is a miss, and any chord slot past its lag window is graded.
  /// Judged on the CORRECTED clock — an on-beat strum arrives via the mic up
  /// to [inputLatencySec] late, so its event must stay open that much longer.
  void advance(double elapsedSec) {
    final playedSec = elapsedSec - inputLatencySec;
    for (final t in _events) {
      if (t.matched) continue;
      if (t.time + windowSec < playedSec) {
        t.matched = true;
        missed++;
        failStreak++;
        combo = 0;
        lastResult = HitResult.missed;
        lastTiming = null;
        lastExpectedDirection = null;
      }
    }
    _evalChords(playedSec);
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
