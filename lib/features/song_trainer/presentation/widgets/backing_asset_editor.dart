import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// The route supplies attachment while detach never deletes shared bytes.
final class BackingAssetEditor extends StatelessWidget {
  const BackingAssetEditor({
    required this.hasBacking,
    required this.onAttach,
    required this.onDetach,
    super.key,
  });

  final bool hasBacking;
  final Future<void> Function() onAttach;
  final VoidCallback onDetach;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.songEditorBacking,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        OutlinedButton(
          key: const Key('song-editor-attach-backing'),
          onPressed: onAttach,
          child: Text(l10n.songEditorAttachBacking),
        ),
        if (hasBacking)
          TextButton(
            onPressed: onDetach,
            child: Text(l10n.songEditorDetachBacking),
          ),
      ],
    );
  }
}
