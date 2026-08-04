import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Attach is supplied by the platform picker in a later route effect; this
/// editor deliberately exposes detach without ever deleting shared bytes.
final class BackingAssetEditor extends StatelessWidget {
  const BackingAssetEditor({
    required this.hasBacking,
    required this.onDetach,
    super.key,
  });

  final bool hasBacking;
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
        if (hasBacking)
          TextButton(
            onPressed: onDetach,
            child: Text(l10n.songEditorDetachBacking),
          ),
      ],
    );
  }
}
