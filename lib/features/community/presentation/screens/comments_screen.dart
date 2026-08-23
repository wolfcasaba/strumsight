/// Community comment sheet screen (E09-R16, ADR 0407 §5, brief §3).
///
/// The per-post comment sheet — a Material 3 bottom sheet that
/// hosts the comments list and the composer for a single post.
/// The screen is a pure projection of [CommentController] — every
/// state transition comes from the controller's state stream.
///
/// **Optimistic create (A6).** The user types a body, taps Send,
/// and the new comment appears in the list immediately with a
/// ``temp-c-...`` local ID. When the server response lands, the
/// controller swaps the temp ID for the real one in a SINGLE atomic
/// state write — the screen rebuilds once and the user sees one
/// row, not two.
///
/// **Draft preservation.** The composer field persists the
/// in-progress body even when the screen is rebuilt — the controller
/// is the source of truth (the Kör 12 ``PostComposerController``
/// draft-store precedent; this round ships the in-memory draft
/// field, a future round can plug the draft store in).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/controllers/comment_controller.dart';
import '../../domain/entities/community_comment.dart';
import '../../domain/value_objects/content_id.dart';

/// The per-post comment sheet. The screen is hosted by the
/// per-post feed card route (a future Kör 17 entry point); this
/// round ships the widget, the controller, and the wiring.
class CommentsScreen extends ConsumerStatefulWidget {
  const CommentsScreen({super.key, required this.postId});

  final ContentId postId;

  @override
  ConsumerState<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends ConsumerState<CommentsScreen> {
  late final TextEditingController _draftController;

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController();
    // Kick off the first-page load as soon as the screen mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(commentControllerProvider.notifier).loadFor(widget.postId);
    });
  }

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commentControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Comments')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (failure, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      failure.toString(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                data: (data) => _CommentsList(
                  rows: data.comments,
                  isLoadingMore: data.isLoadingMore,
                  hasMore:
                      !data.nextCursor.isInitial &&
                      data.nextCursor.cursor != null,
                  onLoadMore: () =>
                      ref.read(commentControllerProvider.notifier).loadMore(),
                ),
              ),
            ),
            _DraftComposer(
              controller: _draftController,
              state: state.value ?? const CommentSheetState.initial(),
              onChanged: (value) => ref
                  .read(commentControllerProvider.notifier)
                  .updateDraft(value),
              onSubmit: () =>
                  ref.read(commentControllerProvider.notifier).submitDraft(),
              onDismissError: () =>
                  ref.read(commentControllerProvider.notifier).clearError(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The scrolling list of comments. The widget is a pure projection
/// of the [CommentSheetState.comments] list — every row comes
/// from a [CommentRow].
class _CommentsList extends StatelessWidget {
  const _CommentsList({
    required this.rows,
    required this.isLoadingMore,
    required this.hasMore,
    required this.onLoadMore,
  });

  final List<CommentRow> rows;
  final bool isLoadingMore;
  final bool hasMore;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('No comments yet.'));
    }
    return ListView.builder(
      itemCount: rows.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= rows.length) {
          // The trailing "load more" row.
          return _LoadMoreRow(isLoading: isLoadingMore, onPressed: onLoadMore);
        }
        final row = rows[index];
        return _CommentTile(comment: row.comment);
      },
    );
  }
}

/// A single comment row. The widget is a pure projection of the
/// ``CommunityComment`` — the temp-vs-real ID distinction lives in
/// the controller's state, not the widget (a single atomic write
/// in the controller keeps the list from ever showing both at
/// once).
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final CommunityComment comment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            comment.authorId.value,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Text(comment.body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _LoadMoreRow extends StatelessWidget {
  const _LoadMoreRow({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(onPressed: onPressed, child: const Text('Load more')),
      ),
    );
  }
}

/// The composer row at the bottom — TextField + Send button. The
/// ``controller`` is owned by the screen (the cursor / focus
/// state is screen-local); the body content is mirrored to the
/// ``CommentController`` via ``onChanged`` so the in-flight submit
/// sees the latest draft.
class _DraftComposer extends StatelessWidget {
  const _DraftComposer({
    required this.controller,
    required this.state,
    required this.onChanged,
    required this.onSubmit,
    required this.onDismissError,
  });

  final TextEditingController controller;
  final CommentSheetState state;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSubmit;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final canSubmit = !state.isSubmitting && state.draftBody.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.lastError != null)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      state.lastError!.toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onDismissError,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  readOnly: state.isSubmitting,
                  onChanged: onChanged,
                  decoration: const InputDecoration(
                    hintText: 'Write a comment…',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 4,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: canSubmit ? onSubmit : null,
                child: state.isSubmitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
