import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Shown when microphone permission is denied. Explains the on-device promise
/// and deep-links to the app settings.
///
/// Shared by every mic-driven screen (Live, Tuner) so a missing permission is
/// never a silent idle.
class MicPermissionBanner extends StatelessWidget {
  const MicPermissionBanner({super.key});

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
          const Icon(Icons.mic_off_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.micPermissionBody,
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
            onPressed: openAppSettings,
            child: Text(l10n.micPermissionAction),
          ),
        ],
      ),
    );
  }
}
