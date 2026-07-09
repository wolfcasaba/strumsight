import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../live/model/strum.dart';

/// An 8-slot (eighth-note) strum-pattern editor. Tapping a slot cycles it
/// rest → down → up → rest, so the user authors the ↓/↑ hand directly — the
/// one thing our engine uniquely scores. Down = copper, up = green (the app's
/// consistent strum semantics).
class StrumPatternEditor extends StatelessWidget {
  const StrumPatternEditor({
    super.key,
    required this.pattern,
    required this.onChanged,
  });

  /// Exactly 8 slots; `null` = rest.
  final List<StrumDirection?> pattern;
  final ValueChanged<List<StrumDirection?>> onChanged;

  static StrumDirection? _next(StrumDirection? d) => switch (d) {
        null => StrumDirection.down,
        StrumDirection.down => StrumDirection.up,
        StrumDirection.up => null,
      };

  // "1 & 2 & 3 & 4 &" — downbeats on even slots.
  static const _labels = ['1', '&', '2', '&', '3', '&', '4', '&'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < pattern.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _Slot(
                dir: pattern[i],
                label: i < _labels.length ? _labels[i] : '',
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
  const _Slot({required this.dir, required this.label, required this.onTap});
  final StrumDirection? dir;
  final String label;
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
    return Column(
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
    );
  }
}
