import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../model/chord.dart';
import '../model/chord_event.dart';
import '../model/strum.dart';
import 'chord_timeline_card.dart';

/// The Live screen's horizontal, right-anchored chord filmstrip.
///
/// The newest chord is the large **hero** on the right; previously recognised
/// chords trail off to the LEFT — progressively smaller, more transparent and
/// slightly blurred — each carrying its own ↓/↑ strum direction. An optional
/// faint "next" ghost sits at the far right when the engine knows what's coming.
///
/// The widget is **pure w.r.t. its data**: it renders entirely from [events]
/// (newest last) so a widget test can pump a fixed list. All motion is
/// `flutter_animate` and finite, so `pumpAndSettle` completes.
class ChordTimeline extends StatelessWidget {
  const ChordTimeline({
    super.key,
    required this.events,
    this.next,
    required this.capo,
    this.listening = true,
    this.beat = 0,
  });

  /// Rolling history, newest LAST. Empty → idle prompt.
  final List<ChordEvent> events;

  /// The chord the engine predicts next, if known (concert pitch).
  final Chord? next;

  /// Capo fret — labels render transposed by `-capo`, buffer stays concert.
  final int capo;

  /// Paused (frozen) timelines dim slightly but keep their history.
  final bool listening;

  /// Monotonic beat index from the engine clock; a new value fires one subtle
  /// hero pulse — 0 disables it. Each pulse is finite (keyed by this index), so
  /// it never repeats forever and `pumpAndSettle` still terminates.
  final int beat;

  /// Size tiers from the hero outward (1.0 = nearest the hero, shrinking left).
  static const _tiers = <double>[1.0, 0.72, 0.55, 0.42];

  double _scaleFor(int distance) {
    final i = (distance - 1).clamp(0, _tiers.length - 1);
    return _tiers[i];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (events.isEmpty) {
      return _emptyState(context, l10n);
    }

    final hero = events.last;
    final history = events.sublist(0, events.length - 1);

    final historyRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < history.length; i++)
          _historyCard(history[i], history.length - i),
      ],
    );

    // A full-width, right-anchored Row so the history region can compress by
    // WIDTH (it's a `Flexible` → bounded width) while the hero keeps its
    // natural size. Each of the hero and the history is independently wrapped
    // in a `FittedBox(scaleDown)` so nothing overflows VERTICALLY on a short
    // Expanded (r187: the earlier whole-strip FittedBox fixed height but shrank
    // the hero with history; a Flexible needs a bounded width, so it can't live
    // inside an outer FittedBox — hence per-part scaleDown instead).
    final strip = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (history.isNotEmpty)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: historyRow,
            ),
          ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: _heroCard(context, hero, beat),
        ),
        if (next != null)
          FittedBox(fit: BoxFit.scaleDown, child: _nextGhost(context, l10n)),
      ],
    );

    return Opacity(
      opacity: listening ? 1.0 : 0.6,
      child: strip,
    );
  }

  // --- Empty state: muted instrument glyph + idle prompt, one gentle pulse ---
  //
  // A single finite fade+scale on the icon (no `.repeat()`), so `pumpAndSettle`
  // still terminates. The `liveWaitingForChord` text is kept verbatim.
  Widget _emptyState(BuildContext context, AppLocalizations l10n) {
    final palette = context.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.graphic_eq,
            size: 40,
            color: palette.muted,
          )
              .animate(key: const ValueKey('empty-pulse'))
              .fadeIn(duration: 400.ms)
              .scaleXY(
                begin: 0.85,
                end: 1.0,
                duration: 400.ms,
                curve: Curves.easeOut,
              ),
          const SizedBox(height: 14),
          Text(
            l10n.liveWaitingForChord,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 20,
              letterSpacing: 0.5,
              color: palette.muted,
            ),
          ),
        ],
      ),
    );
  }

  // --- History card: recede — scale + fade that TWEENS as the card ages ------
  //
  // Each card keeps a stable identity (`ValueKey(seq)`), so when a new chord
  // pushes it further left its target scale/opacity change and the implicit
  // AnimatedScale/AnimatedOpacity animate to the new tier — the spec's "prior
  // cards slide left + scale down + fade, once per transition". (Rendered at
  // base size with `scale: 1.0`; the tier shrink is done here so it can tween.)
  Widget _historyCard(ChordEvent event, int distance) {
    final scale = _scaleFor(distance);
    final opacity = (0.30 + 0.55 * scale).clamp(0.0, 1.0);

    return RepaintBoundary(
      child: AnimatedOpacity(
        key: ValueKey(event.seq),
        opacity: opacity,
        duration: 260.ms,
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: scale,
          duration: 260.ms,
          curve: Curves.easeOut,
          child: ChordTimelineCard(
            event: event,
            isHero: false,
            capo: capo,
          ),
        ),
      ),
    );
  }

  // --- Hero card: spring-in from the right + decoupled recognition flash -----

  Widget _heroCard(BuildContext context, ChordEvent hero, int beat) {
    // Directional strum flourish: down nudges downward, up nudges upward.
    final dirBegin = switch (hero.direction) {
      StrumDirection.down => 0.3,
      StrumDirection.up => -0.3,
      null => 0.0,
    };

    Widget card = ChordTimelineCard(
      key: ValueKey(hero.seq),
      event: hero,
      isHero: true,
      capo: capo,
    );

    // INNERMOST: a single subtle beat-pulse per engine beat. flutter_animate
    // replays a keyed .animate by REMOUNTING it, so this MUST be the innermost
    // wrapper — a beat-index change then remounts only the (cheap, stateless)
    // card below it, NOT the flash/enter animations above it. (If it were the
    // outer wrapper, every beat would remount the whole subtree and replay the
    // spring-in entrance ~2×/sec — a glitch the beat==0 tests never surface.)
    // Finite scale each time, so `pumpAndSettle` still terminates.
    card = card
        .animate(key: ValueKey('beat-$beat'))
        .scaleXY(begin: 1.035, end: 1.0, duration: 150.ms, curve: Curves.easeOut);

    // Middle: recognition flash + micro scale-pulse + directional flourish.
    // Keyed by seq+direction so it re-fires when a strum lands on the same
    // chord (direction/confidence update in place) as well as on a new chord.
    card = card
        .animate(key: ValueKey('flash-${hero.seq}-${hero.direction}'))
        .shimmer(
          duration: 220.ms,
          color: AppColors.primary.withValues(alpha: 0.5),
        )
        .scaleXY(begin: 1.06, end: 1.0, duration: 150.ms, curve: Curves.easeOut)
        .slideY(
          begin: dirBegin,
          end: 0,
          duration: 150.ms,
          curve: Curves.easeOut,
        );

    // OUTERMOST: the spring-in entrance; fire a light haptic on each new hero.
    // Keyed by seq alone so it plays once per NEW chord and is untouched by
    // beat/direction changes (no re-entrance while a chord holds).
    card = card
        .animate(
          key: ValueKey('enter-${hero.seq}'),
          onPlay: (_) => _lightHaptic(),
        )
        .slideX(
          begin: 0.3,
          end: 0,
          duration: 250.ms,
          curve: Curves.easeOutBack,
        )
        .fadeIn(duration: 250.ms)
        .scaleXY(
          begin: 0.9,
          end: 1.0,
          duration: 250.ms,
          curve: Curves.easeOutBack,
        );

    return card;
  }

  // --- Next ghost: faint hint at the hero's right edge ----------------------

  Widget _nextGhost(BuildContext context, AppLocalizations l10n) {
    final palette = context.palette;
    final label = next!.transposed(-capo).label;
    // Fade the ghost in whenever the predicted chord changes (keyed by label),
    // so a new hint appears gently rather than popping. Finite, so
    // `pumpAndSettle` still terminates. The outer `ValueKey('next-ghost')`
    // stays on the returned widget for the existing finder.
    return Opacity(
      key: const ValueKey('next-ghost'),
      opacity: 0.4,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.liveNext.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 11,
                letterSpacing: 2,
                color: palette.muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w700,
                fontSize: 34,
                height: 0.9,
                color: palette.muted,
              ),
            ),
          ],
        ),
      ).animate(key: ValueKey('ghost-$label')).fadeIn(duration: 200.ms),
    );
  }

  void _lightHaptic() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {
      // No-op off-device / in tests.
    }
  }
}
