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
///
/// Layout (audit F1 / A7): the action sits on its OWN line under the
/// icon+message row, the way a [MaterialBanner] lays actions out. The former
/// single-row version put the explanation and a fixed-width text button side
/// by side, so at textScale 2.0 in a narrow column the message was squeezed
/// into a sliver and the row still overflowed horizontally (measured: 167 px
/// at a 258 px width). With the action on its own line the message keeps the
/// full width at every text scale and nothing overflows sideways.
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            // Top-aligned: at a large text scale the message is several
            // lines tall and a centred icon would float mid-paragraph.
            crossAxisAlignment: CrossAxisAlignment.start,
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
            ],
          ),
          // `Align` hands the button LOOSE constraints capped at the banner
          // width, so an over-long (or heavily scaled) label wraps inside
          // the button instead of overflowing the banner.
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: openAppSettings,
              child: Text(l10n.micPermissionAction),
            ),
          ),
        ],
      ),
    );
  }
}
