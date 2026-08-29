import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/public.dart';
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final fatal = preview.warnings.any(
      (warning) => warning.startsWith('fatal.'),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.songImportPreviewTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SsSpacing.space6),
          children: <Widget>[
            Text(
              preview.displayName,
              style: typography.titleLarge.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: SsSpacing.space2),
            Text(
              l10n.songImportFileSize(preview.byteLength),
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: SsSpacing.space2),
            Text(
              '${l10n.songImportFormat}: ${preview.format}',
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (preview.parts.isNotEmpty) ...<Widget>[
              const SizedBox(height: SsSpacing.space4),
              Text(
                l10n.songImportParts,
                style: typography.titleMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              for (final part in preview.parts)
                Text(
                  part.name,
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
            ],
            if (preview.warnings.isNotEmpty) ...<Widget>[
              const SizedBox(height: SsSpacing.space4),
              ImportWarningList(warnings: preview.warnings),
            ],
            const SizedBox(height: SsSpacing.space6),
            SsButton(
              onPressed: fatal
                  ? null
                  : () =>
                        ref.read(songImportControllerProvider).confirmPreview(),
              label: l10n.songImportConfirm,
            ),
            if (fatal)
              Padding(
                padding: const EdgeInsets.only(top: SsSpacing.space2),
                child: Text(
                  l10n.songImportFatalCannotConfirm,
                  style: typography.bodyMedium.copyWith(color: colors.danger),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
