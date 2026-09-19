/// The strumming hand's grid: where a stroke belongs, and which way the hand
/// must be travelling when it gets there.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §3.
/// This is the pillar Yousician does not have — it scores DIRECTION, not only
/// whether a note sounded.
///
/// ## Why direction is derived, not authored
///
/// In continuous eighth-note strumming the direction of a stroke is not a free
/// choice: the on-beat strokes are downstrokes and the off-beats ("&") are
/// upstrokes, because the hand swings like a pendulum and never stops. Teaching
/// sources are unanimous on both halves of that — downstrokes happen on the
/// numbers, upstrokes on the "ands", and the arm keeps moving down-up-down-up
/// with no stops even when it is not strumming on every down or up. A pattern
/// with a hole in it is therefore not a pattern with fewer strokes; it is the
/// same pendulum with some strokes GHOSTED — the hand still travels, it just
/// misses the strings. [StrokeSound.ghost] is that, and it is why a silent slot
/// still carries a direction.
///
/// So [RhythmGrid.pendulum] derives every direction from the slot's position,
/// and an author cannot ask for an upstroke on a beat by accident.
///
/// ## Why an authored escape hatch exists anyway
///
/// The pendulum is the rule for continuous strumming, NOT a law of guitar. The
/// taught 3/4 waltz accompaniment is a documented counterexample: a bass note
/// down on ONE and light chords UP on two and three (oom-pah-pah, strummed
/// "down-up-up"), which this app already ships as the `waltz-time` lesson. A
/// model that called that wrong would be teaching something false about a
/// pattern real teachers teach. [RhythmGrid.authored] exists for those, and
/// [followsPendulum] reports which kind a grid is, so the beginner rungs can
/// require the derived kind without outlawing the rest of music.
///
/// Sources: `docs/research/strumming-direction-pedagogy-2026-09.md`.
///
/// Pure Dart: no Flutter, no clock (AGENTS.md §6/§10).
library;

import 'package:meta/meta.dart';

import '../../../core/music/strum.dart';

/// How fine the pendulum is — one slot per beat, or two.
enum RhythmSubdivision {
  /// Quarter notes. Every slot is on a beat, so every stroke is a DOWNstroke:
  /// the hand's return travel is not a slot at this resolution.
  quarter(slotsPerBeat: 1),

  /// Eighth notes, counted "1 & 2 & 3 & 4 &" — the beginner's strumming grid.
  eighth(slotsPerBeat: 2);

  const RhythmSubdivision({required this.slotsPerBeat});

  /// Slots per quarter-note beat.
  final int slotsPerBeat;
}

/// Whether the hand makes a sound at a slot.
enum StrokeSound {
  /// The strings are struck. Only these slots are notated and scored.
  struck,

  /// The hand travels but does not touch the strings — a "ghost" stroke. The
  /// pendulum never stops, so this slot still has a direction; it simply has
  /// nothing to hear, and nothing to score.
  ghost,
}

/// One slot of the grid.
@immutable
final class RhythmSlot {
  const RhythmSlot({
    required this.index,
    required this.direction,
    required this.sound,
    this.accent = false,
    this.muted = false,
  });

  /// Position in the bar, 0-based.
  final int index;

  /// Which way the hand is travelling here. Derived for a pendulum grid.
  final StrumDirection direction;

  final StrokeSound sound;

  /// Accented (louder) stroke — notated ">".
  final bool accent;

  /// Muted / dampened stroke — notated "x". The right-hand-only rungs are
  /// played this way: the left hand damps, so there is no chord to get wrong.
  final bool muted;

  bool get isStruck => sound == StrokeSound.struck;

  @override
  bool operator ==(Object other) =>
      other is RhythmSlot &&
      other.index == index &&
      other.direction == direction &&
      other.sound == sound &&
      other.accent == accent &&
      other.muted == muted;

  @override
  int get hashCode => Object.hash(index, direction, sound, accent, muted);

  @override
  String toString() {
    final arrow = direction == StrumDirection.down ? 'D' : 'U';
    if (!isStruck) return '($arrow)';
    return '$arrow${accent ? '>' : ''}${muted ? 'x' : ''}';
  }
}

/// One bar of strumming notation, as a grid of slots.
@immutable
final class RhythmGrid {
  const RhythmGrid._({
    required this.slots,
    required this.subdivision,
    required this.beatsPerBar,
  });

  /// A grid whose directions are DERIVED from slot position — the pendulum.
  ///
  /// [struck] has one entry per slot: `true` strikes the strings, `false`
  /// ghosts the stroke. Its length must be `beatsPerBar * slotsPerBeat`, so a
  /// pattern cannot silently spill into the next bar.
  factory RhythmGrid.pendulum({
    required RhythmSubdivision subdivision,
    required List<bool> struck,
    int beatsPerBar = 4,
    Set<int> accents = const {},
    bool muted = false,
  }) {
    final expected = _checkShape(subdivision, beatsPerBar, struck.length);
    _checkAccents(accents, expected, (i) => struck[i]);
    if (!struck.contains(true)) {
      throw ArgumentError.value(
        struck,
        'struck',
        'a grid with nothing to play is not an exercise',
      );
    }
    return RhythmGrid._(
      subdivision: subdivision,
      beatsPerBar: beatsPerBar,
      slots: List<RhythmSlot>.unmodifiable([
        for (var i = 0; i < expected; i++)
          RhythmSlot(
            index: i,
            direction: pendulumDirection(i, subdivision),
            sound: struck[i] ? StrokeSound.struck : StrokeSound.ghost,
            accent: accents.contains(i),
            muted: muted,
          ),
      ]),
    );
  }

  /// A grid whose struck directions are AUTHORED, for patterns that
  /// legitimately depart from the pendulum — the taught waltz is one.
  ///
  /// A `null` entry in [strokes] is a ghost. Its direction is still the
  /// pendulum's, because an unstruck slot is hand travel, not notation.
  factory RhythmGrid.authored({
    required RhythmSubdivision subdivision,
    required List<StrumDirection?> strokes,
    int beatsPerBar = 4,
    Set<int> accents = const {},
    bool muted = false,
  }) {
    final expected = _checkShape(subdivision, beatsPerBar, strokes.length);
    _checkAccents(accents, expected, (i) => strokes[i] != null);
    if (!strokes.any((stroke) => stroke != null)) {
      throw ArgumentError.value(
        strokes,
        'strokes',
        'a grid with nothing to play is not an exercise',
      );
    }
    return RhythmGrid._(
      subdivision: subdivision,
      beatsPerBar: beatsPerBar,
      slots: List<RhythmSlot>.unmodifiable([
        for (var i = 0; i < expected; i++)
          RhythmSlot(
            index: i,
            direction: strokes[i] ?? pendulumDirection(i, subdivision),
            sound: strokes[i] == null ? StrokeSound.ghost : StrokeSound.struck,
            accent: accents.contains(i),
            muted: muted,
          ),
      ]),
    );
  }

  final List<RhythmSlot> slots;
  final RhythmSubdivision subdivision;
  final int beatsPerBar;

  /// Slots in one bar.
  int get slotCount => slots.length;

  /// The slots that make a sound — the only ones that can be scored.
  List<RhythmSlot> get struckSlots =>
      slots.where((slot) => slot.isStruck).toList(growable: false);

  /// Whether every struck stroke travels the way the pendulum would.
  ///
  /// True by construction for [RhythmGrid.pendulum]. The beginner rungs require
  /// it; the `waltz-time` lesson is the counterexample that must not be
  /// outlawed, so this is reported rather than enforced here.
  bool get followsPendulum => slots.every(
    (slot) =>
        !slot.isStruck ||
        slot.direction == pendulumDirection(slot.index, subdivision),
  );

  /// The hand's crossings of the strings, two per beat, each saying whether it
  /// STRIKES.
  ///
  /// An eighth grid already has one slot per crossing. A quarter grid does not:
  /// it notates four downstrokes, but the hand still comes back up between them,
  /// so the returns appear here as ghost crossings. That is the difference
  /// between what is ASKED (the slots, and all that is ever scored) and what the
  /// hand DOES — which is what an animation has to draw, because a hand that
  /// teleported back to the top would be teaching a motion nobody can make.
  List<bool> get handCrossings => switch (subdivision) {
    RhythmSubdivision.eighth => [for (final slot in slots) slot.isStruck],
    RhythmSubdivision.quarter => [
      for (final slot in slots) ...[slot.isStruck, false],
    ],
  };

  /// Microseconds from the start of the exercise to the slot at [slotIndex] of
  /// [bar], at [bpm].
  ///
  /// Integer microseconds, because that is the unit onset evidence arrives in
  /// and the unit the measured tolerance is expressed in. The multiply happens
  /// once on the absolute slot number rather than accumulating a per-slot
  /// rounding error down the bar.
  int onsetUs({required int bar, required int slotIndex, required double bpm}) {
    if (bar < 0) {
      throw ArgumentError.value(bar, 'bar', 'bars are 0-based');
    }
    if (slotIndex < 0 || slotIndex >= slotCount) {
      throw ArgumentError.value(
        slotIndex,
        'slotIndex',
        'outside the bar (0..${slotCount - 1})',
      );
    }
    if (!bpm.isFinite || bpm <= 0) {
      throw ArgumentError.value(
        bpm,
        'bpm',
        'tempo must be finite and positive',
      );
    }
    final slot = bar * slotCount + slotIndex;
    return (slot * 60000000 / (bpm * subdivision.slotsPerBeat)).round();
  }

  /// The direction the hand travels at [index] when the pendulum decides.
  ///
  /// Quarter notes: every slot is on a beat, so every stroke is a downstroke.
  /// Eighths: on-beat slots are down, the "&" slots are up.
  static StrumDirection pendulumDirection(
    int index,
    RhythmSubdivision subdivision,
  ) => subdivision == RhythmSubdivision.quarter || index.isEven
      ? StrumDirection.down
      : StrumDirection.up;

  static int _checkShape(
    RhythmSubdivision subdivision,
    int beatsPerBar,
    int given,
  ) {
    if (beatsPerBar <= 0) {
      throw ArgumentError.value(
        beatsPerBar,
        'beatsPerBar',
        'a bar needs at least one beat',
      );
    }
    final expected = beatsPerBar * subdivision.slotsPerBeat;
    if (given != expected) {
      throw ArgumentError.value(
        given,
        'strokes',
        'a $beatsPerBar-beat bar of ${subdivision.name}s needs $expected '
            'slots, not $given — a short pattern would spill into the next bar',
      );
    }
    return expected;
  }

  static void _checkAccents(
    Set<int> accents,
    int slotCount,
    bool Function(int) isStruck,
  ) {
    for (final accent in accents) {
      if (accent < 0 || accent >= slotCount) {
        throw ArgumentError.value(
          accent,
          'accents',
          'accent is outside the bar (0..${slotCount - 1})',
        );
      }
      if (!isStruck(accent)) {
        throw ArgumentError.value(
          accent,
          'accents',
          'a ghosted slot cannot be accented — there is nothing to hear',
        );
      }
    }
  }
}
