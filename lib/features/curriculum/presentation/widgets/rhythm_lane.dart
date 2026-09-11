/// The notation row: which chord is struck, which way, and what was heard.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §3.
/// Research: `docs/research/visual-rhythm-cues-2026-09.md`.
///
/// The arrows are the STANDARD convention (↓ down, ↑ up, following the hand's
/// travel), so what a learner reads here transfers to real tab. Colour is
/// redundant everywhere: direction is carried by the glyph's shape, and every
/// fretting state also carries a word. That is deliberate — colour-coded
/// notation measurably helps beginners and measurably becomes a crutch when it
/// is the only channel.
library;

import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/music/strum.dart';
import '../../domain/rhythm_grid.dart';

/// What the recogniser can honestly say about the chord being held.
enum FrettingState {
  /// Confirmed, and it is the chord that was asked for. The only green state.
  ringing,

  /// Nothing confirmed — mid-change, or too quiet. Not a failure.
  unconfirmed,

  /// Confirmed, but a different chord.
  otherChord,
}

/// One bar of notation: the chord above, the strokes below.
final class RhythmLane extends StatelessWidget {
  const RhythmLane({
    super.key,
    required this.grid,
    required this.chord,
    required this.fretting,
    this.activeSlotIndex,
    this.prepareSlotIndexes = const {},
    this.heardChord,
    this.barLabel,
  });

  final RhythmGrid grid;

  /// The chord to hold, or null for the damped right-hand-only rungs. Null is
  /// rendered as an explicit "no chord" line rather than an empty gap: a muted
  /// string has no chord to name, and a blank space reads as an oversight.
  final String? chord;

  final FrettingState fretting;

  /// Which notated slot is sounding now, in grid-slot indices.
  final int? activeSlotIndex;

  /// Slots where the left hand should already be moving to the next shape. The
  /// one thing a chord-only recogniser cannot teach and this app can.
  final Set<int> prepareSlotIndexes;

  /// The chord actually confirmed, when it is not the one asked for.
  final String? heardChord;

  final String? barLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (barLabel != null) ...[
          Text(
            barLabel!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: SsSpacing.space2),
        ],
        _chordBar(context, l10n, colors),
        const SizedBox(height: SsSpacing.space2),
        Row(
          children: [
            for (var i = 0; i < grid.slots.length; i++)
              Expanded(child: _slot(context, l10n, colors, i)),
          ],
        ),
      ],
    );
  }

  Widget _chordBar(
    BuildContext context,
    AppLocalizations l10n,
    SsColorScheme colors,
  ) {
    final name = chord;
    if (name == null) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SsSpacing.space3,
          vertical: SsSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: BorderRadius.circular(SsRadius.sm),
          border: Border.all(color: colors.border),
        ),
        child: Text(
          l10n.curriculumNoChord,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      );
    }
    final accent = _frettingColor(colors);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SsSpacing.space3,
        vertical: SsSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: Color.lerp(colors.surfaceSunken, accent, 0.16),
        borderRadius: BorderRadius.circular(SsRadius.sm),
        border: Border.all(
          color: accent,
          // Unconfirmed is visibly thinner rather than a different hue only, so
          // the state survives without colour.
          width: fretting == FrettingState.unconfirmed ? 1 : 2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.curriculumHoldChord.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: SsSpacing.space2),
          Text(
            name,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: SsSpacing.space2),
          // The word, always — never colour alone (red/green merges for the
          // most common colour-vision deficiency, and green/amber is no safer
          // as a sole channel).
          Flexible(
            child: Text(
              _frettingWord(l10n),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slot(
    BuildContext context,
    AppLocalizations l10n,
    SsColorScheme colors,
    int index,
  ) {
    final slot = grid.slots[index];
    final isActive = index == activeSlotIndex;
    final isPrepare = prepareSlotIndexes.contains(index);
    final direction = slot.direction == StrumDirection.down
        ? SsStrumDirection.down
        : SsStrumDirection.up;
    final label = slot.direction == StrumDirection.down
        ? l10n.curriculumStrokeDown
        : l10n.curriculumStrokeUp;
    return Semantics(
      label: slot.isStruck
          ? l10n.curriculumStrokeSemantic(_countLabel(index), label)
          : l10n.curriculumStrokeGhost,
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(vertical: SsSpacing.space2),
        decoration: BoxDecoration(
          color: isActive
              ? Color.lerp(Colors.transparent, colors.brand, 0.16)
              : isPrepare
              ? Color.lerp(Colors.transparent, colors.info, 0.12)
              : null,
          borderRadius: BorderRadius.circular(SsRadius.sm),
          border: Border(
            bottom: BorderSide(
              // The preparation window gets an underline, not just a tint: the
              // cue has to survive a greyscale screenshot.
              color: isPrepare ? colors.info : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 26,
              child: slot.isStruck
                  ? Center(
                      child: SsStrumGlyph(
                        direction: direction,
                        // Tier 2 is the filled head: this is notation, what the
                        // learner is ASKED to play, not a confidence reading.
                        confidenceTier: 2,
                        color: colors.brand,
                        size: 16,
                      ),
                    )
                  : Center(
                      child: SsStrumGlyph(
                        direction: direction,
                        // Tier 0 — the hollow chevron — for a ghost: the hand
                        // travels, nothing is struck.
                        confidenceTier: 0,
                        color: colors.textDisabled,
                        size: 13,
                      ),
                    ),
            ),
            const SizedBox(height: 2),
            Text(
              _countLabel(index),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _isOnBeat(index)
                    ? colors.textPrimary
                    : colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: _isOnBeat(index)
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isOnBeat(int index) => index % grid.subdivision.slotsPerBeat == 0;

  /// "1 & 2 & 3 & 4 &" — the count a teacher says out loud, which is why the
  /// off-beats are "&" and not a number.
  String _countLabel(int index) {
    final perBeat = grid.subdivision.slotsPerBeat;
    final beat = index ~/ perBeat;
    return index % perBeat == 0 ? '${beat + 1}' : '&';
  }

  Color _frettingColor(SsColorScheme colors) => switch (fretting) {
    // Green is the confirmed-evidence colour, shared with the grading: it may
    // only appear when the recogniser actually confirmed the asked chord.
    FrettingState.ringing => colors.success,
    // Amber, never red. A different chord is information, not an error.
    FrettingState.otherChord => colors.warning,
    FrettingState.unconfirmed => colors.border,
  };

  String _frettingWord(AppLocalizations l10n) => switch (fretting) {
    FrettingState.ringing => l10n.curriculumChordRinging,
    FrettingState.otherChord => l10n.curriculumChordOther(heardChord ?? '?'),
    FrettingState.unconfirmed => l10n.curriculumChordUnclear,
  };
}
