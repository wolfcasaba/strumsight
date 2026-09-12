/// What the app plays before a listen-and-repeat attempt, and the gap after it.
///
/// ## Why a demonstration can teach this pattern at all
///
/// [RhythmMode.listenAndRepeat] takes the arrow row away on purpose, so the ear is
/// the only channel left. That raises an obvious objection: the app's only sound is a
/// click, and a click cannot convey whether a stroke was a DOWN or an UP — which is
/// the very thing the pillar scores.
///
/// The objection dissolves, and the reason is the same one the grid is built on.
/// Within continuous strumming, direction is not free information: on-beat strokes
/// are downstrokes and the "ands" are upstrokes, because the hand swings and never
/// stops (`rhythm_grid.dart`,
/// `docs/research/strumming-direction-pedagogy-2026-09.md`). The teaching sources on
/// learning a strum pattern BY EAR describe exactly this division of labour — zero in
/// on the recurring rhythmic idea, tap it out, vocalise it with neutral syllables,
/// explicitly without deciding which syllable any given attack is. What the ear
/// supplies is WHEN. The pendulum supplies WHICH WAY.
///
/// So the demonstration is honest precisely because it is rhythm-only, and two things
/// follow that are decisions rather than details:
///
///   - **The click must NOT encode direction.** A higher pitch meaning "up" would
///     teach a cue that does not exist on a guitar — the app would be inventing a
///     sound the instrument does not make. The accent marks beat 1 of the bar, which
///     is metre, and metre is true.
///   - **The mode is only honest on a pendulum grid.** If a grid's struck directions
///     depart from the pendulum — the taught 3/4 waltz does, legitimately — then the
///     demonstration carries the timing and NOTHING carries the departure, because
///     the notation is hidden. Scoring direction there would fault a learner for
///     information they were never given. `RhythmAssignment` refuses that
///     combination outright rather than leaving it to an author's care.
///
/// ## The shape, and why it has a silent bar in it
///
/// ```
///   | demo bar 1 | demo bar 2 | SILENT bar | count-in bar | bar 1 ... (scored)
/// ```
///
/// **Two demonstration bars, not one.** The sources' first step is recognising the
/// *recurring* rhythmic idea; a single presentation of a one-bar pattern gives
/// nothing to recognise as recurring.
///
/// **One silent bar, on the metre.** Two independent reasons, and the first alone is
/// enough. With a single click timbre the demonstration and the count-in would
/// otherwise run together — and for a quarter-note pattern they would be literally
/// identical, so a learner could not hear where "listen" ended and "play" began. And
/// it keeps the pulse the demonstration just established, which an off-metre pause
/// would break.
///
/// MEASURED (`test/features/live/demonstration_preroll_test.dart`): this pre-roll is
/// heard by the engine as 15 strokes, every one of them falls outside the attempt so
/// the existing count-in rule drops them, and the attempt itself is reported
/// identically to a silent-pre-roll control — every stroke within 5 ms. The risk that
/// twenty clicks re-tune the adaptive onset front end, and that a learner is then
/// graded against a threshold their own demonstration raised, was measured rather
/// than reasoned about.
///
/// Pure Dart: no Flutter, no clock, no audio (AGENTS.md §6/§10). WHICH sound plays is
/// `metronome_pulse.dart`'s decision; this file says WHEN and WHETHER ACCENTED.
library;

import 'package:meta/meta.dart';

import 'rhythm_assignment.dart';
import 'rhythm_mode.dart';

/// How many times the app plays the pattern before handing it over.
const int demonstrationBars = 2;

/// Bars of silence between the demonstration and the count-in.
const int demonstrationGapBars = 1;

/// One stroke the app sounds while demonstrating.
@immutable
final class RhythmDemoStroke {
  const RhythmDemoStroke({required this.atUs, required this.accent});

  /// Microseconds from the start of the demonstration.
  final int atUs;

  /// Beat 1 of a demonstration bar, which is the only thing a single click timbre
  /// can mark. Never direction.
  final bool accent;

  @override
  bool operator ==(Object other) =>
      other is RhythmDemoStroke && other.atUs == atUs && other.accent == accent;

  @override
  int get hashCode => Object.hash(atUs, accent);

  @override
  String toString() => '${atUs}us${accent ? '>' : ''}';
}

/// The pre-roll of a demonstrating mode: the played bars, then the silent bar.
@immutable
final class RhythmDemonstration {
  const RhythmDemonstration._({
    required this.bars,
    required this.gapBars,
    required this.barUs,
    required this.strokes,
  });

  /// The demonstration [assignment] calls for, or **null** when its mode does not
  /// demonstrate.
  ///
  /// Null rather than an empty demonstration: "plays nothing first" and "has no
  /// first phase" are different timelines, and collapsing them would shift every
  /// other mode's bar 1 by the gap bar.
  static RhythmDemonstration? forAssignment(RhythmAssignment assignment) {
    if (!assignment.mode.demonstratesFirst) return null;
    final grid = assignment.grid;
    final barUs = (60000000 / assignment.bpm * grid.beatsPerBar).round();
    return RhythmDemonstration._(
      bars: demonstrationBars,
      gapBars: demonstrationGapBars,
      barUs: barUs,
      strokes: List<RhythmDemoStroke>.unmodifiable([
        for (var bar = 0; bar < demonstrationBars; bar++)
          for (final slot in grid.struckSlots)
            RhythmDemoStroke(
              atUs:
                  bar * barUs +
                  grid.onsetUs(
                    bar: 0,
                    slotIndex: slot.index,
                    bpm: assignment.bpm,
                  ),
              // Beat 1 of the bar. A struck slot that does not land on beat 1 is
              // never accented, so the accent cannot be mistaken for emphasis the
              // learner is meant to reproduce.
              accent: slot.index == 0,
            ),
      ]),
    );
  }

  /// Bars of the pattern that are played.
  final int bars;

  /// Bars of silence after them.
  final int gapBars;

  final int barUs;

  /// Every stroke the app sounds, in order, timed from the demonstration's start.
  final List<RhythmDemoStroke> strokes;

  /// While the pattern is sounding.
  int get playingUs => bars * barUs;

  /// The whole pre-roll this adds before the count-in — the played bars AND the
  /// silent one.
  int get totalUs => (bars + gapBars) * barUs;

  /// Whether [atUs] (from the demonstration's start) is in the silent bar.
  ///
  /// The UI needs this as its own question: the silence is not dead time to hide, it
  /// is the "now you" beat, and a screen that showed nothing there would look like
  /// it had stalled.
  bool isGap(int atUs) => atUs >= playingUs && atUs < totalUs;

  /// Which demonstration bar is playing at [atUs], 1-based, or null outside the
  /// played bars — so "bar 2 of 2" can be shown without the screen doing metre
  /// arithmetic of its own.
  int? barNumberAt(int atUs) {
    if (atUs < 0 || atUs >= playingUs || barUs <= 0) return null;
    return atUs ~/ barUs + 1;
  }

  @override
  bool operator ==(Object other) =>
      other is RhythmDemonstration &&
      other.bars == bars &&
      other.gapBars == gapBars &&
      other.barUs == barUs &&
      _sameStrokes(other.strokes, strokes);

  @override
  int get hashCode =>
      Object.hash(bars, gapBars, barUs, Object.hashAll(strokes));

  static bool _sameStrokes(
    List<RhythmDemoStroke> a,
    List<RhythmDemoStroke> b,
  ) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((same) => same);
}
