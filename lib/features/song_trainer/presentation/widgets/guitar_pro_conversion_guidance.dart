import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Read-only guidance for converting a user's own Guitar Pro file locally.
final class GuitarProConversionGuidance extends StatelessWidget {
  const GuitarProConversionGuidance({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.songImportGuitarProGuidanceSemantics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              l10n.songImportGuitarProTitle,
              style: textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          Text(l10n.songImportGuitarProBody),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(
              l10n.songImportGuitarProStepsTitle,
              style: textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Text(l10n.songImportGuitarProSteps),
        ],
      ),
    );
  }
}
