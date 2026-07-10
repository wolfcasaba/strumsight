import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Shown when the microphone could not be started (in use by another app,
/// revoked mid-capture, platform channel error). Offers a Retry.
///
/// Shared by every mic-driven screen (Live since round 13, Tuner since
/// round 68) so a mic failure is never a silent no-op.
class MicErrorBanner extends StatelessWidget {
  const MicErrorBanner({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.micErrorBody,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                height: 1.35,
                color: palette.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            child: Text(l10n.micErrorAction),
          ),
        ],
      ),
    );
  }
}
