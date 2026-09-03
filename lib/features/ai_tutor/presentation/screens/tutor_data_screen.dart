/// Tutor Data screen (E04-R22 §3).
///
/// User-facing surface for:
///
/// * Memory-fact list (`tutorMemoryFactsProvider`) — read/edit/delete
///   through the repository's `update()` / `delete()`. Each row exposes
///   an edit button that opens a dialog with a `TextEditingController`;
///   on save the row calls `repo.update(fact.copyWith(content, updatedAt))`
///   and surfaces the localized "sensitive" error (`ValidationFailure`
///   from the repo's sensitivity filter) or a generic edit failure
///   message, depending on the `AppFailure` subtype returned.
/// * Conversation list (`tutorConversationsProvider`) — one row per
///   conversation with a per-row delete button.
/// * Redacted export — calls `TutorMemoryRepository.exportRedacted()`,
///   which the repo guarantees substitutes `'[redacted]'` for every
///   fact `content` (§6 acceptance).
/// * Delete-all — the destructive primary action shows the EXACT scope
///   list inline (wrapped in `Key('tutorDataDeleteAllScopeList')` so the
///   row-count assertion in `R22-F2` detects any scope drift) and, on
///   tap, opens a one-shot confirmation dialog whose final button calls
///   `deleteAllAiData()`. The dialog also repeats the scope list so the
///   user cannot miss it.
///
/// All write paths funnel through the `tutorMemoryRepositoryProvider`
/// / `tutorConversationRepositoryProvider` seams so the widgets are
/// fake-repository testable (R17 + R18 test pattern).
///
/// Design-system migration (E15-R09): this screen's own pinned widget test
/// (`tutor_data_screen_test.dart`) is wired with `theme: SsLightTheme.data()`
/// (§0.0.A/R3), so theme-extension `Ss*` components are safe here. Both
/// `FutureProvider.when` error branches are practically unreachable today
/// (`tutorMemoryFactsProvider`/`tutorConversationsProvider` in
/// `tutor_privacy_providers.dart` already collapse a repository `Failure`
/// to an empty list/page rather than rethrowing — measured), but they must
/// still compile and render something reasonable, so they get the same
/// [SsFailureState] treatment as a genuinely reachable failure would.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/components/actions/ss_button.dart';
import '../../../../core/design_system/components/feedback/failure_presentation.dart';
import '../../../../core/design_system/components/feedback/ss_failure_state.dart';
import '../../../../core/design_system/components/feedback/ss_skeleton.dart';
import '../../../../core/design_system/components/surfaces/ss_card.dart';
import '../../../../core/design_system/foundations/ss_spacing.dart';
import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/storage/storage_keys.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/tutor_conversation.dart';
import '../../domain/models/tutor_memory_fact.dart';
import '../../domain/repositories/tutor_conversation_repository.dart';
import '../../domain/repositories/tutor_memory_repository.dart';
import '../providers/tutor_privacy_providers.dart';
import '../providers/tutor_providers.dart';

class TutorDataScreen extends ConsumerWidget {
  const TutorDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final memoryFacts = ref.watch(tutorMemoryFactsProvider);
    final conversations = ref.watch(tutorConversationsProvider);
    final memoryRepo = ref.read(tutorMemoryRepositoryProvider);
    final conversationRepo = ref.read(tutorConversationRepositoryProvider);

    Future<void> handleExportRedacted() async {
      final result = await memoryRepo.exportRedacted();
      if (!context.mounted) return;
      switch (result) {
        case Success<String>(:final value):
          await showDialog<void>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: Text(l10n.tutorDataExportRedactedTitle),
                content: SingleChildScrollView(child: Text(value)),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(l10n.commonClose),
                  ),
                ],
              );
            },
          );
        case Failure<String>():
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.tutorDataExportFailed)));
      }
    }

    Future<void> confirmAndDeleteAll() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(l10n.tutorDataDeleteAllTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.tutorDataDeleteAllBody),
                  const SizedBox(height: SsSpacing.space3),
                  Text(l10n.tutorDataDeleteAllScopePreserved),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.tutorDataDeleteAllCancel),
              ),
              FilledButton(
                key: const Key('tutorDataDeleteAllConfirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.tutorDataDeleteAllConfirm),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
      final result = await memoryRepo.deleteAllAiData();
      if (!context.mounted) return;
      if (result.isSuccess) {
        ref.invalidate(tutorMemoryFactsProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.tutorDataDeleteAllDone)));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.tutorDataDeleteAllFailed)));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tutorDataTitle)),
      body: SafeArea(
        child: Semantics(
          container: true,
          label: l10n.tutorDataScreenSemantics,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SsSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.tutorDataIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: SsSpacing.space4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SsButton(
                    key: const Key('tutorDataExportRedacted'),
                    onPressed: handleExportRedacted,
                    icon: Icons.download_outlined,
                    label: l10n.tutorDataExportRedactedAction,
                  ),
                ),
                const SizedBox(height: SsSpacing.space6),
                Text(
                  l10n.tutorDataMemoryTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: SsSpacing.space2),
                memoryFacts.when(
                  data: (facts) {
                    if (facts.isEmpty) {
                      return Text(l10n.tutorDataMemoryEmpty);
                    }
                    return Column(
                      children: <Widget>[
                        for (final fact in facts)
                          _MemoryFactRow(fact: fact, repo: memoryRepo),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(SsSpacing.space4),
                    child: Center(
                      child: SsSkeleton(width: double.infinity, height: 56),
                    ),
                  ),
                  error: (_, _) => Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SsSpacing.space2,
                    ),
                    child: SsFailureState(
                      presentation: SsFailurePresentation.from(
                        l10n,
                        const UnknownFailure(retryable: true),
                      ),
                      onRetry: () => ref.invalidate(tutorMemoryFactsProvider),
                    ),
                  ),
                ),
                const SizedBox(height: SsSpacing.space6),
                Text(
                  l10n.tutorDataConversationsTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: SsSpacing.space2),
                conversations.when(
                  data: (page) {
                    if (page.items.isEmpty) {
                      return Text(l10n.tutorDataConversationsEmpty);
                    }
                    return Column(
                      children: <Widget>[
                        for (final item in page.items)
                          _ConversationRow(
                            conversation: item,
                            repo: conversationRepo,
                          ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(SsSpacing.space4),
                    child: Center(
                      child: SsSkeleton(width: double.infinity, height: 56),
                    ),
                  ),
                  error: (_, _) => Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SsSpacing.space2,
                    ),
                    child: SsFailureState(
                      presentation: SsFailurePresentation.from(
                        l10n,
                        const UnknownFailure(retryable: true),
                      ),
                      onRetry: () => ref.invalidate(tutorConversationsProvider),
                    ),
                  ),
                ),
                const SizedBox(height: SsSpacing.space8),
                Text(
                  l10n.tutorDataDeleteAllScopeTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: SsSpacing.space2),
                Container(
                  key: const Key('tutorDataDeleteAllScopeList'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final key in StorageKeys.tutorAiData)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('•'),
                              const SizedBox(width: 8),
                              Expanded(child: Text(key)),
                            ],
                          ),
                        ),
                      for (final key in StorageKeys.tutorAiData)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('•'),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  StorageKeys.quarantineOf(key),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: SsSpacing.space3),
                Text(l10n.tutorDataDeleteAllScopePreserved),
                const SizedBox(height: SsSpacing.space3),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SsButton(
                    key: const Key('tutorDataDeleteAllTrigger'),
                    onPressed: confirmAndDeleteAll,
                    variant: SsButtonVariant.secondary,
                    icon: Icons.delete_forever_outlined,
                    label: l10n.tutorDataDeleteAllAction,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryFactRow extends ConsumerWidget {
  const _MemoryFactRow({required this.fact, required this.repo});

  final TutorMemoryFact fact;
  final TutorMemoryRepository repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(fact.content),
          const SizedBox(height: SsSpacing.space2),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: SsSpacing.space2,
            children: <Widget>[
              TextButton(
                key: Key('tutorDataMemoryEdit:${fact.id}'),
                onPressed: () => _openEditDialog(context, ref),
                child: Text(l10n.tutorDataMemoryEdit),
              ),
              TextButton(
                key: Key('tutorDataMemoryDelete:${fact.id}'),
                onPressed: () async {
                  await repo.delete(fact.id);
                  ref.invalidate(tutorMemoryFactsProvider);
                },
                child: Text(l10n.tutorDataMemoryDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openEditDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _MemoryFactEditDialog(
          fact: fact,
          repo: repo,
          invalidateFacts: () => ref.invalidate(tutorMemoryFactsProvider),
        );
      },
    );
  }
}

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({required this.conversation, required this.repo});

  final TutorConversation conversation;
  final TutorConversationRepository repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: ListTile(
        title: Text(conversation.id.value),
        trailing: TextButton(
          key: Key('tutorDataConversationDelete:${conversation.id.value}'),
          onPressed: () async {
            await repo.delete(conversation.id);
            ref.invalidate(tutorConversationsProvider);
          },
          child: Text(l10n.tutorDataConversationDelete),
        ),
      ),
    );
  }
}

class _MemoryFactEditDialog extends StatefulWidget {
  const _MemoryFactEditDialog({
    required this.fact,
    required this.repo,
    required this.invalidateFacts,
  });

  final TutorMemoryFact fact;
  final TutorMemoryRepository repo;
  final VoidCallback invalidateFacts;

  @override
  State<_MemoryFactEditDialog> createState() => _MemoryFactEditDialogState();
}

class _MemoryFactEditDialogState extends State<_MemoryFactEditDialog> {
  late final TextEditingController _controller;
  String? _errorText;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.fact.content);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showError() async {
    final message = _errorText;
    if (message == null) return;
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: Key('tutorDataMemoryEditErrorDialog:${widget.fact.id}'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.commonClose),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);
    final newContent = _controller.text.trim();
    if (newContent.isEmpty) {
      setState(() => _errorText = l10n.tutorDataMemoryEditEmpty);
      await _showError();
      return;
    }
    setState(() => _submitting = true);
    final updated = widget.fact.copyWith(
      content: newContent,
      updatedAt: DateTime.now().toUtc(),
    );
    final result = await widget.repo.update(updated);
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (result) {
      case Success<void>():
        widget.invalidateFacts();
        if (mounted) {
          Navigator.of(context).pop();
        }
      case Failure<void>(:final error):
        setState(() {
          _errorText = error is ValidationFailure
              ? l10n.tutorDataMemoryEditSensitive
              : l10n.tutorDataMemoryEditFailed;
        });
        await _showError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: Key('tutorDataMemoryEditDialog:${widget.fact.id}'),
      title: Text(l10n.tutorDataMemoryEditTitle),
      content: TextField(
        key: Key('tutorDataMemoryEditField:${widget.fact.id}'),
        controller: _controller,
        autofocus: true,
        maxLines: 3,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.tutorDataMemoryEditCancel),
        ),
        FilledButton(
          key: Key('tutorDataMemoryEditSave:${widget.fact.id}'),
          onPressed: _submitting ? null : _submit,
          child: Text(l10n.tutorDataMemoryEditSave),
        ),
      ],
    );
  }
}
