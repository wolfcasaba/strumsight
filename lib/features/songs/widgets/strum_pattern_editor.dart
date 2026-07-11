import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../live/model/strum.dart';

/// A one-bar (eighth-note) strum-pattern editor — 8 slots in 4/4, 6 in 3/4.
/// Tapping a slot cycles it rest → down → up → rest, so the user authors the
/// ↓/↑ hand directly — the one thing our engine uniquely scores. Down =
/// copper, up = green (the app's consistent strum semantics).
class StrumPatternEditor extends StatelessWidget {
  const StrumPatternEditor({
    super.key,
    required this.pattern,
    required this.onChanged,
  });

  /// One bar of slots (beatsPerBar × 2); `null` = rest.
  final List<StrumDirection?> pattern;
  final ValueChanged<List<StrumDirection?>> onChanged;

  static StrumDirection? _next(StrumDirection? d) => switch (d) {
        null => StrumDirection.down,
        StrumDirection.down => StrumDirection.up,
        StrumDirection.up => null,
      };

  /// "1 & 2 & …" up to the bar's own beat count (round 116 — 3/4 support).
  static String _label(int slot) => slot.isEven ? '${slot ~/ 2 + 1}' : '&';

  /// Spoken beat position for a screen reader (round 125): "1" for a downbeat,
  /// "1 and" for the off-beat eighth between beats 1 and 2.
  static String _spokenPosition(AppLocalizations l10n, int slot) =>
      slot.isEven ? '${slot ~/ 2 + 1}' : l10n.songSlotAnd(slot ~/ 2 + 1);

  static String _stateWord(AppLocalizations l10n, StrumDirection? dir) =>
      switch (dir) {
        StrumDirection.down => l10n.strumDown,
        StrumDirection.up => l10n.strumUp,
        null => l10n.strumRest,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        for (var i = 0; i < pattern.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _Slot(
                dir: pattern[i],
                label: _label(i),
                // The icon-only button was invisible to a screen reader
                // (round 125 a11y): announce beat + state + that it toggles.
                semanticLabel: l10n.songSlotSemantic(
                  _spokenPosition(l10n, i),
                  _stateWord(l10n, pattern[i]),
                ),
                onTap: () {
                  final next = [...pattern];
                  next[i] = _next(pattern[i]);
                  onChanged(next);
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.dir,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });
  final StrumDirection? dir;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDown = dir == StrumDirection.down;
    final isUp = dir == StrumDirection.up;
    final color = isDown
        ? AppColors.primary
        : isUp
            ? AppColors.confidenceHigh
            : Theme.of(context).colorScheme.outline;
    // One button node speaking beat+state; the icon and beat glyph are visual
    // only, so exclude their (redundant / "ampersand") semantics (round 125).
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: dir == null
                    ? Colors.transparent
                    : color.withValues(alpha: 0.15),
                border: Border.all(color: color.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isDown
                    ? Icons.arrow_downward
                    : isUp
                        ? Icons.arrow_upward
                        : Icons.remove,
                size: 20,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }
}
