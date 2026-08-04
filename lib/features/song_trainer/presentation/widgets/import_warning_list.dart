import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Warning list whose fatal entries remain visually and semantically distinct.
final class ImportWarningList extends StatelessWidget {
  const ImportWarningList({required this.warnings, super.key});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) => ListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: warnings.length,
    itemBuilder: (context, index) {
      final warning = warnings[index];
      final fatal = warning.startsWith('fatal.');
      final l10n = AppLocalizations.of(context);
      return Semantics(
        label: fatal
            ? l10n.songImportFatalSemantic(warning)
            : l10n.songImportWarningSemantic(warning),
        child: ListTile(
          leading: Icon(
            fatal ? Icons.error_outline : Icons.warning_amber_outlined,
            color: fatal ? Theme.of(context).colorScheme.error : Colors.orange,
          ),
          title: Text(warning),
        ),
      );
    },
  );
}
