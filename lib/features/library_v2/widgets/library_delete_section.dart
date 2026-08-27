import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';
import '../../../core/foundation/app_result.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/library_delete_actions.dart';
import '../domain/library_delete_scope.dart';
import '../domain/library_item.dart';
import 'library_theme_scope.dart';

/// The storage-management entry point (§5.3/§5.4): every button here only
/// STATES the scope's consequence and, on confirm, delegates to
/// [LibraryDeleteActions] — the real deletion always happens inside the
/// existing repository/port, never in this widget (A5).
///
/// **NEM elfogadható gyengítés (§5.3):** a generic "Delete? Yes/No" with no
/// named scope — see the round's real-violation probe (§10).
final class LibraryDeleteSection extends StatelessWidget {
  const LibraryDeleteSection({
    super.key,
    required this.item,
    required this.actions,
    required this.onDeleted,
  });

  final AnalysisLibraryItem item;
  final LibraryDeleteActions actions;

  /// Called with the use case's [AppResult] once deletion resolves — the
  /// caller decides how to react to a failure (e.g. keep the item visible
  /// and surface an error), never this widget (A5).
  final ValueChanged<AppResult<void>> onDeleted;

  Future<void> _confirm(
    BuildContext context,
    AppLocalizations l10n,
    LibraryDeleteScope scope,
  ) {
    final (title, consequence, confirmLabel) = switch (scope) {
      LibraryDeleteScope.rawOnly => (
        l10n.libraryV2DeleteRawTitle,
        l10n.libraryV2DeleteRawConsequence,
        l10n.libraryV2DeleteRawAction,
      ),
      LibraryDeleteScope.resultOnly => (
        l10n.libraryV2DeleteResultTitle,
        l10n.libraryV2DeleteResultConsequence,
        l10n.libraryV2DeleteResultAction,
      ),
      LibraryDeleteScope.everything => (
        l10n.libraryV2DeleteEverythingTitle,
        l10n.libraryV2DeleteEverythingConsequence,
        l10n.libraryV2DeleteEverythingAction,
      ),
    };
    return showLibraryConfirmationSheet(
      context,
      title: title,
      consequence: consequence,
      confirmLabel: confirmLabel,
      cancelLabel: l10n.libraryV2DeleteCancel,
      onConfirm: () {
        unawaited(actions.delete(item.id, scope).then(onDeleted));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SsSection(
      title: l10n.libraryV2DeleteSectionTitle,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (item.hasRawAudio)
            OutlinedButton(
              key: const ValueKey('library-delete-raw-only'),
              onPressed: () =>
                  _confirm(context, l10n, LibraryDeleteScope.rawOnly),
              child: Text(l10n.libraryV2DeleteRawAction),
            ),
          if (item.hasResult)
            OutlinedButton(
              key: const ValueKey('library-delete-result-only'),
              onPressed: () =>
                  _confirm(context, l10n, LibraryDeleteScope.resultOnly),
              child: Text(l10n.libraryV2DeleteResultAction),
            ),
          FilledButton(
            key: const ValueKey('library-delete-everything'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () =>
                _confirm(context, l10n, LibraryDeleteScope.everything),
            child: Text(l10n.libraryV2DeleteEverythingAction),
          ),
        ],
      ),
    );
  }
}
