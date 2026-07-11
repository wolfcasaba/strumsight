import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../analyze/model/analyze_result.dart';
import '../../live/model/strum.dart';
import '../../streak/daily_challenge.dart';

/// One thing to play at a point in a lesson: a strum (with a direction) on a
/// chord, timed in **beats** from the lesson start (eighth-note resolution →
/// `beat` can be x.0 or x.5).
@immutable
class LessonEvent {
  const LessonEvent({
    required this.beat,
    required this.chord,
    required this.direction,
  });

  final double beat;

  /// The chord to fret when this stroke lands ('' = strum-only / muted).
  final String chord;
  final StrumDirection direction;

  bool get isDown => direction == StrumDirection.down;
}

/// Skill tier of a lesson (drives grouping + progression in the library).
enum Difficulty { beginner, intermediate, advanced }

/// A play-along lesson: a chord progression (one chord per bar) played with a
/// repeating strum pattern, at a fixed tempo. Expanded to a flat, timed
/// [events] list that the highway animation scrolls toward the strike line.
///
/// The strum pattern is 8 eighth-note slots per 4/4 bar; a null slot is a rest.
@immutable
class Lesson {
  /// Build from a chord-per-bar progression + a repeating 8-slot strum pattern.
  Lesson({
    required this.id,
    required this.name,
    required this.bpm,
    required List<String> chords,
    required List<StrumDirection?> pattern,
    this.difficulty = Difficulty.beginner,
    this.beatsPerBar = 4,
  })  : events = _expand(chords, pattern, beatsPerBar),
        totalBeats = chords.length * beatsPerBar.toDouble();

  /// Build directly from a timed event list (e.g. an imported Analyze clip).
  const Lesson.fromEvents({
    required this.id,
    required this.name,
    required this.bpm,
    required this.events,
    required this.totalBeats,
    this.difficulty = Difficulty.beginner,
    this.beatsPerBar = 4,
  });

  final String id;
  final String name;
  final double bpm;
  final Difficulty difficulty;
  final int beatsPerBar;

  /// The flattened, beat-timed strokes.
  final List<LessonEvent> events;

  /// Total length in beats (a trailing bar of ring-out is NOT included).
  final double totalBeats;

  static List<LessonEvent> _expand(
    List<String> chords,
    List<StrumDirection?> pattern,
    int beatsPerBar,
  ) {
    // Two slots per beat (8ths): a mismatched pattern would silently spill
    // its tail into the NEXT bar, overlapping the following chord (round 114).
    assert(pattern.length == beatsPerBar * 2,
        'pattern has ${pattern.length} slots but $beatsPerBar beats/bar '
        'needs ${beatsPerBar * 2}');
    final out = <LessonEvent>[];
    for (var bar = 0; bar < chords.length; bar++) {
      for (var slot = 0; slot < pattern.length; slot++) {
        final dir = pattern[slot];
        if (dir == null) continue;
        out.add(LessonEvent(
          beat: bar * beatsPerBar + slot * 0.5,
          chord: chords[bar],
          direction: dir,
        ));
      }
    }
    return out;
  }

  /// A beginner-friendly cut of this lesson: **down-strokes on the beat only**,
  /// so a learner nails the chord changes first, before adding up-strokes and
  /// off-beats (chunk 016b P4 "dynamic difficulty"). Falls back to the full
  /// lesson if it has no on-beat down-strokes (e.g. a purely off-beat reggae
  /// skank), so it can never yield an unplayable empty lesson.
  Lesson get simplified {
    final kept =
        events.where((e) => e.isDown && e.beat % 1.0 == 0).toList();
    if (kept.isEmpty || kept.length == events.length) return this;
    return Lesson.fromEvents(
      id: id,
      name: name,
      bpm: bpm,
      events: kept,
      totalBeats: totalBeats,
      difficulty: difficulty,
      beatsPerBar: beatsPerBar,
    );
  }

  /// The distinct chords in play order (for a header / "chords used" line).
  List<String> get chordSequence {
    final seen = <String>[];
    for (final e in events) {
      if (e.chord.isNotEmpty && (seen.isEmpty || seen.last != e.chord)) {
        seen.add(e.chord);
      }
    }
    return seen;
  }
}

// Shorthand for building patterns.
const _d = StrumDirection.down;
const _u = StrumDirection.up;

/// The built-in starter lessons (grow later into a full library).
class Lessons {
  Lessons._();

  // ---- Beginner ----

  /// All-downstrokes on the beat — the absolute beginner's first strum.
  static Lesson get firstStrums => Lesson(
        id: 'first-strums',
        name: 'First Strums',
        bpm: 70,
        chords: const ['Em', 'Em', 'G', 'G'],
        pattern: const [_d, null, _d, null, _d, null, _d, null],
      );

  /// Practising a clean chord change on every downstroke.
  static Lesson get twoChordChange => Lesson(
        id: 'two-chord-change',
        name: 'Two-Chord Change',
        bpm: 74,
        chords: const ['Am', 'C', 'Am', 'C'],
        pattern: const [_d, null, _d, null, _d, null, _d, null],
      );

  /// Eighth-note down-strokes — steady and driving.
  static Lesson get eighthDrive => Lesson(
        id: 'eighth-drive',
        name: 'Eighth-Note Drive',
        bpm: 80,
        chords: const ['G', 'G', 'D', 'D'],
        pattern: const [_d, _d, _d, _d, _d, _d, _d, _d],
      );

  /// The I–vi–IV–V "50s" doo-wop progression.
  static Lesson get fiftiesDooWop => Lesson(
        id: 'fifties-doo-wop',
        name: 'Fifties Doo-Wop',
        bpm: 82,
        chords: const ['C', 'Am', 'F', 'G'],
        pattern: const [_d, null, _d, null, _d, null, _d, null],
      );

  /// Two one-finger-apart shapes (Em7 ↔ Cmaj7) — chord CHANGES with almost
  /// no left-hand work, so the right hand can focus on the beat.
  static Lesson get twoFingerFrame => Lesson(
        id: 'two-finger-frame',
        name: 'Two-Finger Frame',
        bpm: 72,
        chords: const ['Em7', 'Cmaj7', 'Em7', 'Cmaj7'],
        pattern: const [_d, null, _d, null, _d, null, _d, null],
      );

  // ---- Intermediate ----

  /// The ubiquitous D-DU-UDU pop/folk pattern over a I–V–vi–IV progression.
  static Lesson get downUpGroove => Lesson(
        id: 'down-up-groove',
        name: 'Down-Up Groove',
        bpm: 90,
        difficulty: Difficulty.intermediate,
        chords: const ['C', 'G', 'Am', 'F'],
        pattern: const [_d, null, _d, _u, null, _u, _d, _u],
      );

  /// A folk pattern with a syncopated push.
  static Lesson get folkPattern => Lesson(
        id: 'folk-pattern',
        name: 'Folk Fingers',
        bpm: 96,
        difficulty: Difficulty.intermediate,
        chords: const ['G', 'Em', 'C', 'D'],
        pattern: const [_d, null, _d, _u, _d, _u, _d, _u],
      );

  /// Introduces a barre chord (Bm) in a common minor-key progression.
  static Lesson get barreGroove => Lesson(
        id: 'barre-groove',
        name: 'Barre Groove',
        bpm: 92,
        difficulty: Difficulty.intermediate,
        chords: const ['Bm', 'G', 'D', 'A'],
        pattern: const [_d, null, _d, _u, null, _u, _d, _u],
      );

  /// An anthemic G–D–Em–C with the classic down-up feel.
  static Lesson get anthemDrive => Lesson(
        id: 'anthem-drive',
        name: 'Anthem Drive',
        bpm: 98,
        difficulty: Difficulty.intermediate,
        chords: const ['G', 'D', 'Em', 'C'],
        pattern: const [_d, null, _d, _u, null, _u, _d, _u],
      );

  /// A minor "rising" progression with a steady down-up arpeggio feel.
  static Lesson get risingMinor => Lesson(
        id: 'rising-minor',
        name: 'Rising Minor',
        bpm: 86,
        difficulty: Difficulty.intermediate,
        chords: const ['Am', 'C', 'D', 'F'],
        pattern: const [_d, _u, _d, _u, _d, _u, _d, _u],
      );

  /// The app's first 3/4 lesson: bass on ONE, light strums on two and three
  /// (oom-pah-pah). Waltz time is where 4/4 habits go to be found out.
  static Lesson get waltzTime => Lesson(
        id: 'waltz-time',
        name: 'Waltz Time',
        bpm: 84,
        difficulty: Difficulty.intermediate,
        beatsPerBar: 3,
        chords: const ['C', 'F', 'C', 'G'],
        pattern: const [_d, null, _u, null, _u, null],
      );

  // ---- Advanced ----

  /// Off-beat up-strokes — a reggae-style skank.
  static Lesson get reggaeSkank => Lesson(
        id: 'reggae-skank',
        name: 'Reggae Skank',
        bpm: 100,
        difficulty: Difficulty.advanced,
        chords: const ['Am', 'Dm', 'Am', 'E'],
        pattern: const [null, _u, null, _u, null, _u, null, _u],
      );

  /// Busy sixteenth-ish funk with alternating strokes.
  static Lesson get funkChop => Lesson(
        id: 'funk-chop',
        name: 'Funk Chop',
        bpm: 104,
        difficulty: Difficulty.advanced,
        chords: const ['Em', 'Em', 'A', 'A'],
        pattern: const [_d, _u, _d, _u, _d, _u, _d, _u],
      );

  /// A dominant-7 blues shuffle over A7–D7.
  static Lesson get bluesShuffle => Lesson(
        id: 'blues-shuffle',
        name: 'Blues Shuffle',
        bpm: 100,
        difficulty: Difficulty.advanced,
        chords: const ['A7', 'A7', 'D7', 'A7'],
        pattern: const [_d, null, _d, _u, _d, null, _d, _u],
      );

  /// Syncopation drill: after the downbeat, everything lands on the "and"s —
  /// the strumming hand must keep moving through the silent downstrokes.
  static Lesson get pushAndPull => Lesson(
        id: 'push-and-pull',
        name: 'Push & Pull',
        bpm: 96,
        difficulty: Difficulty.advanced,
        chords: const ['Am', 'G', 'F', 'E'],
        pattern: const [_d, null, null, _u, null, _u, null, _u],
      );

  static List<Lesson> get all => [
        firstStrums,
        twoChordChange,
        eighthDrive,
        fiftiesDooWop,
        twoFingerFrame,
        downUpGroove,
        folkPattern,
        barreGroove,
        anthemDrive,
        risingMinor,
        waltzTime,
        reggaeSkank,
        funkChop,
        bluesShuffle,
        pushAndPull,
      ];

  /// Lessons of a given tier, in curriculum order.
  static List<Lesson> byDifficulty(Difficulty d) =>
      all.where((l) => l.difficulty == d).toList();

  /// The curriculum successor of [id], or null for the last lesson and for
  /// one-off lessons (daily challenges, Analyze imports) that live outside
  /// the curriculum (round 92 — the finish→next retention loop).
  static Lesson? nextAfter(String id) {
    final lessons = all;
    for (var i = 0; i < lessons.length - 1; i++) {
      if (lessons[i].id == id) return lessons[i + 1];
    }
    return null;
  }

  /// Turn a recorded [AnalyzeResult] into a play-along lesson — practise a riff
  /// you (or a song) just played. Each detected strum becomes a timed event on
  /// the chord that was sounding then; the tempo is the clip's detected BPM.
  static Lesson fromAnalyze(AnalyzeResult result, {required String name}) {
    final bpm = result.bpm > 0 ? result.bpm : 90.0;
    final secPerBeat = 60.0 / bpm;
    final strums = [...result.strums]
      ..sort((a, b) => a.timeSec.compareTo(b.timeSec));
    final t0 = strums.isEmpty ? 0.0 : strums.first.timeSec;
    final events = <LessonEvent>[
      for (final s in strums)
        LessonEvent(
          beat: (s.timeSec - t0) / secPerBeat,
          chord: _chordAt(result.chords, s.timeSec),
          direction: s.direction,
        ),
    ];
    final lastBeat = events.isEmpty ? 0.0 : events.last.beat;
    // Extend to the end of the bar that CONTAINS the last event (so it fits),
    // minimum one bar.
    final bars = math.max(1, (lastBeat / 4).floor() + 1);
    return Lesson.fromEvents(
      id: 'analyze-import',
      name: name,
      bpm: bpm,
      events: events,
      totalBeats: bars * 4.0,
      difficulty: Difficulty.intermediate,
    );
  }

  static String _chordAt(List<TimelineChord> chords, double t) {
    for (final c in chords) {
      if (t >= c.startSec && t < c.endSec) return c.label;
    }
    return '';
  }

  /// Turn today's [DailyChallenge] into a one-bar, strum-only play-along so the
  /// streak challenge is *playable*, not just shown (ties chunk 013 together).
  static Lesson fromDailyChallenge(DailyChallenge c, {double bpm = 80}) {
    // Map the challenge's arrows onto eighth-note slots (down-beats first).
    final slots = List<StrumDirection?>.filled(8, null);
    for (var i = 0; i < c.pattern.length && i < 8; i++) {
      slots[i] = c.pattern[i];
    }
    return Lesson(
      id: 'daily-${c.day}',
      name: c.name,
      bpm: bpm,
      chords: const [''],
      pattern: slots,
    );
  }
}
