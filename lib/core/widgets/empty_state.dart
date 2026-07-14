import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_palette.dart';

/// A shared, theme-tokened first-run / empty-screen placeholder: a muted
/// [icon], a [title], and an optional [subtitle], centered in a constrained
/// column. Replaces the bespoke per-screen empties (Library, Progress, Songs,
/// Analyze idle) so they read consistently (round 190).
///
/// Set [pulse] for a ONE-SHOT entrance animation on the icon (fade-in +
/// scale-up). It is finite — no `.repeat()` — so widget tests that call
/// `pumpAndSettle` still settle.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.pulse = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget iconWidget = Icon(icon, size: 40, color: palette.muted);
    if (pulse) {
      iconWidget = iconWidget
          .animate(key: const ValueKey('empty-state-pulse'))
          .fadeIn(duration: 400.ms)
          .scaleXY(
            begin: 0.85,
            end: 1.0,
            duration: 400.ms,
            curve: Curves.easeOut,
          );
    }

    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 18,
              height: 1.35,
              color: palette.ink,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                height: 1.45,
                color: palette.muted,
              ),
            ),
          ],
        ],
      ),
    );

    // "Center, but scroll if too tall": centers in the available space, and
    // never overflows when the parent is short (small portrait / landscape /
    // mid-navigation-transition frames) — the canonical scroll-view + minHeight
    // idiom. Falls back to a plain Center if the parent leaves height unbounded.
    return LayoutBuilder(
      builder: (context, constraints) {
        final padded = Padding(
          padding: const EdgeInsets.all(24),
          child: content,
        );
        if (!constraints.hasBoundedHeight) {
          return Center(child: padded);
        }
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: padded),
          ),
        );
      },
    );
  }
}
