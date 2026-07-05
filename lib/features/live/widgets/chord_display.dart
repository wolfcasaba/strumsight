import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../model/chord.dart';

/// The hero of the Live screen: the huge current chord with the next chord
/// ghosted above it. Readable at arm's length while both hands are on the neck.
class ChordDisplay extends StatelessWidget {
  const ChordDisplay({super.key, required this.current, this.next});

  final Chord? current;
  final Chord? next;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 20,
          child: next == null
              ? null
              : Text(
                  '${l10n.liveNext.toUpperCase()} · ${next!.label}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: 2,
                    color: palette.muted,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            current?.label ?? '—',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
              fontSize: 132,
              height: 0.9,
              letterSpacing: -4,
              color: palette.ink,
            ),
          ),
        ),
      ],
    );
  }
}
