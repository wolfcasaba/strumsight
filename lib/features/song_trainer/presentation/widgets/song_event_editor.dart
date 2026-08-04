import 'package:flutter/material.dart';

import '../../../../core/music/strum.dart';
import '../../../../l10n/app_localizations.dart';

final class SongEventEditor extends StatelessWidget {
  const SongEventEditor({
    required this.onAddChord,
    required this.onApplyPattern,
    required this.onAddNote,
    super.key,
  });

  final VoidCallback onAddChord;
  final void Function(List<StrumDirection>) onApplyPattern;
  final VoidCallback onAddNote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      children: <Widget>[
        OutlinedButton(
          onPressed: onAddChord,
          child: Text(l10n.songEditorAddChord),
        ),
        OutlinedButton(
          onPressed: () => onApplyPattern(const <StrumDirection>[
            StrumDirection.down,
            StrumDirection.up,
          ]),
          child: Text(l10n.songEditorApplyPattern),
        ),
        OutlinedButton(
          onPressed: onAddNote,
          child: Text(l10n.songEditorAddNote),
        ),
      ],
    );
  }
}
