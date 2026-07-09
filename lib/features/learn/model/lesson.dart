import 'package:flutter/foundation.dart';

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

/// A play-along lesson: a chord progression (one chord per bar) played with a
/// repeating strum pattern, at a fixed tempo. Expanded to a flat, timed
/// [events] list that the highway animation scrolls toward the strike line.
///
/// The strum pattern is 8 eighth-note slots per 4/4 bar; a null slot is a rest.
@immutable
class Lesson {
  Lesson({
    required this.id,
    required this.name,
    required this.bpm,
    required this.chords,
    required this.pattern,
    this.beatsPerBar = 4,
  }) : events = _expand(chords, pattern, beatsPerBar);

  final String id;
  final String name;
  final double bpm;
  final int beatsPerBar;

  /// One chord per bar (cycled if the lesson runs longer than the list).
  final List<String> chords;

  /// 8 eighth-note slots per bar; down / up / null (rest).
  final List<StrumDirection?> pattern;

  /// The flattened, beat-timed strokes.
  final List<LessonEvent> events;

  int get bars => chords.length;

  /// Total length in beats (a trailing bar of ring-out is NOT included).
  double get totalBeats => bars * beatsPerBar.toDouble();

  static List<LessonEvent> _expand(
    List<String> chords,
    List<StrumDirection?> pattern,
    int beatsPerBar,
  ) {
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

  /// The distinct chords in play order (for a header / "chords used" line).
  List<String> get chordSequence {
    final seen = <String>[];
    for (final c in chords) {
      if (c.isNotEmpty && (seen.isEmpty || seen.last != c)) seen.add(c);
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

  /// All-downstrokes on the beat — the absolute beginner's first strum.
  static Lesson get firstStrums => Lesson(
        id: 'first-strums',
        name: 'First Strums',
        bpm: 70,
        chords: const ['Em', 'Em', 'G', 'G'],
        pattern: const [_d, null, _d, null, _d, null, _d, null],
      );

  /// The ubiquitous D-DU-UDU pop/folk pattern over a I–V–vi–IV progression.
  static Lesson get downUpGroove => Lesson(
        id: 'down-up-groove',
        name: 'Down-Up Groove',
        bpm: 90,
        chords: const ['C', 'G', 'Am', 'F'],
        pattern: const [_d, null, _d, _u, null, _u, _d, _u],
      );

  static List<Lesson> get all => [firstStrums, downUpGroove];

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
