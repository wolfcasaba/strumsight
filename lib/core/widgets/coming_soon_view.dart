import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// A tasteful empty state for features shipping in v2 (Analyze, Library).
class ComingSoonView extends StatelessWidget {
  const ComingSoonView({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: palette.muted),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                l10n.comingSoonV2.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w800,
                fontSize: 26,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  height: 1.45,
                  color: palette.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
