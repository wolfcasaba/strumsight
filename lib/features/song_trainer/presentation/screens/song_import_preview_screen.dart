import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/import/import_preview.dart';
import '../../application/song_trainer_providers.dart';
import '../widgets/import_warning_list.dart';

final class SongImportPreviewScreen extends ConsumerWidget {
  const SongImportPreviewScreen({required this.preview, super.key});

  final ImportPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final fatal = preview.warnings.any(
      (warning) => warning.startsWith('fatal.'),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.songImportPreviewTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text(
              preview.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(l10n.songImportFileSize(preview.byteLength)),
            const SizedBox(height: 8),
            Text('${l10n.songImportFormat}: ${preview.format}'),
            if (preview.parts.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(l10n.songImportParts),
              for (final part in preview.parts) Text(part.name),
            ],
            if (preview.warnings.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              ImportWarningList(warnings: preview.warnings),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: fatal
                  ? null
                  : () =>
                        ref.read(songImportControllerProvider).confirmPreview(),
              child: Text(l10n.songImportConfirm),
            ),
            if (fatal)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.songImportFatalCannotConfirm,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
