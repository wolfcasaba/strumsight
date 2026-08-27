import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/public.dart';
import '../../../core/foundation/app_result.dart';
import '../../../l10n/app_localizations.dart';
import '../../audio_analysis/public.dart';
import '../../share/public.dart';
import '../domain/library_item.dart';
import '../providers/library_v2_providers.dart';
import '../widgets/library_delete_section.dart';
import '../widgets/library_theme_scope.dart';

/// The unified item detail screen (UI-41, `/profile/library/session/:sessionId`).
///
/// Switches on [LibraryItem]'s runtime type (A1) — a corrupt source renders
/// an isolated failure state instead of crashing (A2), and every type's
/// content stays fully reachable while the item's own copy is offline (A3,
/// §5.2): nothing here depends on a live network call.
final class LibraryItemDetailScreen extends ConsumerWidget {
  const LibraryItemDetailScreen({super.key, required this.item});

  final LibraryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = item;
    return LibraryThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(_titleFor(l10n, current))),
        body: SafeArea(
          child: switch (current) {
            CorruptLibraryItem(:final reasonCode) => _CorruptBody(
              l10n: l10n,
              reasonCode: reasonCode,
            ),
            AnalysisLibraryItem() => _AnalysisDetailBody(item: current),
            PracticeLibraryItem(:final title, :final createdAt) =>
              _MetadataBody(
                title: title,
                timestampLabel: l10n.libraryV2MetadataRecordedOn(
                  createdAt.toIso8601String(),
                ),
                typeLabel: l10n.libraryV2TypePractice,
              ),
            SongLibraryItem(:final title, :final artist, :final updatedAt) =>
              _MetadataBody(
                title: title,
                timestampLabel: l10n.libraryV2MetadataUpdatedOn(
                  updatedAt.toIso8601String(),
                ),
                typeLabel: artist ?? l10n.libraryV2TypeSong,
              ),
            SetlistLibraryItem(
              :final title,
              :final songCount,
              :final updatedAt,
            ) =>
              _MetadataBody(
                title: title,
                timestampLabel: l10n.libraryV2MetadataUpdatedOn(
                  updatedAt.toIso8601String(),
                ),
                typeLabel: l10n.setlistV2ItemCount(songCount),
              ),
          },
        ),
      ),
    );
  }

  String _titleFor(AppLocalizations l10n, LibraryItem item) => switch (item) {
    CorruptLibraryItem() => l10n.libraryV2CorruptSourceTitle,
    AnalysisLibraryItem(:final title) => title,
    PracticeLibraryItem(:final title) => title,
    SongLibraryItem(:final title) => title,
    SetlistLibraryItem(:final title) => title,
  };
}

class _CorruptBody extends StatelessWidget {
  const _CorruptBody({required this.l10n, required this.reasonCode});

  final AppLocalizations l10n;
  final String reasonCode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    return Center(
      key: const ValueKey('library-detail-corrupt'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.danger, size: 40),
            const SizedBox(height: 16),
            Text(
              l10n.libraryV2CorruptSourceMessage,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              reasonCode,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataBody extends StatelessWidget {
  const _MetadataBody({
    required this.title,
    required this.timestampLabel,
    required this.typeLabel,
  });

  final String title;
  final String timestampLabel;
  final String typeLabel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('library-detail-metadata'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(typeLabel, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(timestampLabel, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _AnalysisDetailBody extends ConsumerStatefulWidget {
  const _AnalysisDetailBody({required this.item});

  final AnalysisLibraryItem item;

  @override
  ConsumerState<_AnalysisDetailBody> createState() =>
      _AnalysisDetailBodyState();
}

class _AnalysisDetailBodyState extends ConsumerState<_AnalysisDetailBody> {
  late final TextEditingController _notesController;
  AppResult<void>? _lastDeleteResult;

  @override
  void initState() {
    super.initState();
    // Ephemeral in this round — no notes storage/use case exists on the tree
    // yet (§0.0/B3 measured only delete owners); the field demonstrates the
    // interaction and is not persisted across a screen re-entry.
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleExport(BuildContext context) async {
    final repository = ref.read(analysisRepositoryProvider);
    final result = await repository.getById(widget.item.id);
    if (!context.mounted) return;
    switch (result) {
      case Success<AnalysisDocument>(:final value):
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => AnalysisExportScreen(
              document: value,
              exportUseCase: ExportAnalysisUseCase(
                shareService: const ShareService(),
                tempDirectory: Directory.systemTemp,
              ),
            ),
          ),
        );
      case Failure<AnalysisDocument>():
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.libraryV2ExportUnavailable)),
        );
    }
  }

  void _handleDeleted(AppResult<void> result) {
    if (!mounted) return;
    setState(() => _lastDeleteResult = result);
    ref.read(libraryV2ItemsProvider.notifier).reload();
    final l10n = AppLocalizations.of(context);
    if (result.isSuccess) {
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.libraryV2DeleteFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    return ListView(
      key: const ValueKey('library-detail-analysis'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          l10n.libraryV2MetadataRecordedOn(item.createdAt.toIso8601String()),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        SsSection(
          title: l10n.libraryV2ResultSectionTitle,
          child: Text(
            // A6 — even without a retained raw capture, the result stays
            // openable; A3 — this reads only [item], never a network call,
            // so the item's own copy opens the same way offline.
            item.hasResult
                ? l10n.libraryV2ResultAvailable
                : l10n.libraryV2ResultMissing,
          ),
        ),
        if (!item.hasRawAudio) ...[
          const SizedBox(height: 8),
          Text(
            l10n.libraryV2RawAudioMissingNotice,
            key: const ValueKey('library-detail-raw-missing-notice'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        SsSection(
          title: l10n.libraryV2NotesSectionTitle,
          child: SsTextField(
            label: l10n.libraryV2NotesFieldLabel,
            controller: _notesController,
            maxLines: 4,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          key: const ValueKey('library-detail-export'),
          onPressed: () => _handleExport(context),
          child: Text(l10n.libraryV2ExportAction),
        ),
        const SizedBox(height: 16),
        LibraryDeleteSection(
          item: item,
          actions: ref.watch(libraryV2DeleteActionsProvider),
          onDeleted: _handleDeleted,
        ),
        if (_lastDeleteResult case Failure<void>()) ...[
          const SizedBox(height: 8),
          Text(
            l10n.libraryV2DeleteFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
