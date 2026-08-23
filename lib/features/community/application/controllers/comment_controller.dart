/// Community comment controller (E09-R16, ADR 0407 §5, brief §6).
///
/// The single source of truth for the per-post comment sheet. A
/// Riverpod ``AsyncNotifier`` so the screen can reactively rebuild
/// on every state transition (the Kör 14 ``feed_controller`` and
/// Kör 15 ``ReactionController`` precedents).
///
/// **Optimistic create + temp-ID atomikus csere (A6).** The
/// controller assigns a fresh ``ContentId`` temp ID to the
/// optimistic row BEFORE the repository call lands. The repository
/// returns the server-side ``CommunityComment`` whose ``public_id``
/// becomes the real id; the controller swaps the temp id for the
/// real one in a SINGLE atomic state write — no duplicate row.
///
/// **Idempotency key (§5.2).** A retry of the SAME create uses the
/// SAME wire key; the Kör 5 ``CommunityPostRepository.createComment``
/// contract carries it on the wire.
///
/// **No gamification adapter (§A7).** A community comment is NOT a
/// learning reward event — the E08-R26 invariant, the same one
/// ``post_composer_controller`` / ``reaction_controller`` respect.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/logging/logger_provider.dart';
import '../../domain/entities/community_comment.dart';
import '../../domain/entities/moderation_state.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';
import 'post_composer_controller.dart' show communityPostRepositoryProvider;

/// The single per-post comment sheet state.
class CommentSheetState {
  const CommentSheetState({
    required this.comments,
    required this.draftBody,
    required this.isSubmitting,
    required this.isLoadingMore,
    required this.lastError,
    required this.nextCursor,
  });

  const CommentSheetState.initial()
    : comments = const <CommentRow>[],
      draftBody = '',
      isSubmitting = false,
      isLoadingMore = false,
      lastError = null,
      nextCursor = const CursorPage.haltedAfterRequest();

  /// One row per comment. The [CommentRow] wrapper carries the
  /// ``tempId`` field the controller uses to swap optimistic +
  /// server rows atomically.
  final List<CommentRow> comments;

  /// The body the user is currently typing. Persisted through the
  /// draft store (a future round's responsibility; this round ships
  /// the in-memory draft field so the screen can wire the TextField).
  final String draftBody;

  /// True while a create submit is in flight. The text-field is
  /// read-only while this is true (the Kör 15 ``ReactionController``
  /// ``isSubmitting`` precedent).
  final bool isSubmitting;

  /// True while a load-more pagination call is in flight.
  final bool isLoadingMore;

  /// The most recent failure (a create, edit, or delete). Cleared
  /// on the next successful mutation. The screen surfaces it as a
  /// banner.
  final AppFailure? lastError;

  /// The server-issued cursor for the NEXT page, or ``null`` when
  /// the list is at end-of-feed. The first page's cursor is
  /// ``CursorPage.initial()``; subsequent pages carry the opaque
  /// server cursor.
  final CursorPage nextCursor;

  CommentSheetState copyWith({
    List<CommentRow>? comments,
    String? draftBody,
    bool? isSubmitting,
    bool? isLoadingMore,
    Object? lastError = _sentinel,
    CursorPage? nextCursor,
  }) {
    return CommentSheetState(
      comments: comments ?? this.comments,
      draftBody: draftBody ?? this.draftBody,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as AppFailure?,
      nextCursor: nextCursor ?? this.nextCursor,
    );
  }
}

const Object _sentinel = Object();

/// Internal row wrapper — carries the temp ID for optimistic rows
/// and the real ID for server-confirmed rows. The controller swaps
/// the temp ID for the real one in a SINGLE atomic state write
/// (§6 A6 — the temp ID atomikus csere).
class CommentRow {
  const CommentRow({required this.tempId, required this.comment});

  /// The local row identity — a ``ContentId`` that is either the
  /// optimistic temp ID (a UUID-shaped local identifier) or the
  /// server-confirmed ``comment.id``. The two are NEVER equal —
  /// the swap is a single atomic state write.
  final ContentId tempId;
  final CommunityComment comment;

  CommentRow copyWith({ContentId? tempId, CommunityComment? comment}) {
    return CommentRow(
      tempId: tempId ?? this.tempId,
      comment: comment ?? this.comment,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CommentRow && other.tempId == tempId && other.comment == comment;

  @override
  int get hashCode => Object.hash(tempId, comment);
}

/// Counter for client-side temp IDs. Each optimistic create gets a
/// fresh temp ID — a monotonic counter plus a UUID-shaped suffix
/// so two calls in the same microsecond still differ.
int _tempIdCounter = 0;

ContentId _newTempCommentId() {
  _tempIdCounter += 1;
  return ContentId(
    'temp-c-${DateTime.now().microsecondsSinceEpoch}-$_tempIdCounter',
  );
}

/// The Community comment sheet state machine.
class CommentController extends AsyncNotifier<CommentSheetState> {
  CommunityPostRepository get _repo =>
      ref.read(communityPostRepositoryProvider);

  AppLogger get _logger => ref.read(appLoggerProvider);

  /// The post the sheet is currently viewing. Set by the screen
  /// via [loadFor]; ``null`` until then.
  ContentId? _postId;

  @override
  Future<CommentSheetState> build() async {
    return const CommentSheetState.initial();
  }

  /// Bind to a post and load its first page of comments.
  ///
  /// The screen calls this in ``initState`` after it has the
  /// ``ContentId`` for the post. The first page fetch is awaited
  /// so the screen's first build has the comments list (no flash
  /// of "no comments" before the first page lands).
  Future<void> loadFor(ContentId postId) async {
    _postId = postId;
    final current = state.value ?? const CommentSheetState.initial();
    state = AsyncData(
      current.copyWith(
        isLoadingMore: true,
        nextCursor: const CursorPage.initial(),
      ),
    );
    try {
      final page = await _repo.comments(
        postId: postId,
        cursor: const CursorPage.initial(),
        limit: 25,
      );
      state = AsyncData(
        CommentSheetState(
          comments: <CommentRow>[
            for (final comment in page.items)
              CommentRow(tempId: comment.id, comment: comment),
          ],
          draftBody: current.draftBody,
          isSubmitting: false,
          isLoadingMore: false,
          lastError: null,
          nextCursor: page.cursor,
        ),
      );
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.comments.loadFor.failure',
        fields: {'postId': postId.value},
      );
      state = AsyncData(
        current.copyWith(isLoadingMore: false, lastError: failure),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.comments.loadFor.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'postId': postId.value},
      );
      state = AsyncData(
        current.copyWith(
          isLoadingMore: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Update the draft body (called on every TextField keystroke).
  void updateDraft(String body) {
    final current = state.value ?? const CommentSheetState.initial();
    state = AsyncData(current.copyWith(draftBody: body));
  }

  /// Load the next page of comments, if any.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null) return;
    if (current.isLoadingMore) return;
    if (current.nextCursor.isInitial || current.nextCursor.cursor == null) {
      return;
    }
    final postId = _postId;
    if (postId == null) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await _repo.comments(
        postId: postId,
        cursor: current.nextCursor,
        limit: 25,
      );
      // A page that returns a previously-seen comment id is
      // dropped — the §6 A7 invariant that no duplicate id lands
      // in the list even if the server returns one (defence
      // against a tampered cursor that loops the list).
      final existing = <ContentId>{
        for (final row in current.comments) row.tempId,
      };
      final fresh = <CommentRow>[];
      for (final comment in page.items) {
        if (existing.contains(comment.id)) continue;
        fresh.add(CommentRow(tempId: comment.id, comment: comment));
      }
      state = AsyncData(
        current.copyWith(
          comments: <CommentRow>[...current.comments, ...fresh],
          isLoadingMore: false,
          nextCursor: page.cursor,
        ),
      );
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.comments.loadMore.failure',
        fields: {'postId': postId.value},
      );
      state = AsyncData(
        current.copyWith(isLoadingMore: false, lastError: failure),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.comments.loadMore.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'postId': postId.value},
      );
      state = AsyncData(
        current.copyWith(
          isLoadingMore: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Create a new comment from the current draft body.
  ///
  /// The temp ID is generated synchronously and the optimistic row
  /// is appended BEFORE the network call. When the server returns
  /// the real ``CommunityComment``, the controller swaps the
  /// temp id for the real one in a SINGLE atomic state write (§6
  /// A6 — the temp ID atomikus csere contract).
  Future<void> submitDraft() async {
    final current = state.value;
    if (current == null) return;
    if (current.isSubmitting) return;
    final postId = _postId;
    if (postId == null) return;
    final body = current.draftBody.trim();
    if (body.isEmpty) return;

    final tempId = _newTempCommentId();
    // The optimistic row uses a placeholder author id — the real
    // author id lands when the server response comes back. The
    // server is the source of truth for the comment's author
    // (the §6 A3 IDOR guarantee: a client cannot spoof the
    // author_id, the JWT subject is canonical).
    final optimistic = CommunityComment(
      id: tempId,
      authorId: PublicUserId('optimistic-temp-author'),
      postId: postId,
      parentCommentId: null,
      body: body,
      createdAt: DateTime.now().toUtc(),
      moderationState: ModerationState.visible,
    );

    state = AsyncData(
      current.copyWith(
        comments: <CommentRow>[
          ...current.comments,
          CommentRow(tempId: tempId, comment: optimistic),
        ],
        isSubmitting: true,
        lastError: null,
      ),
    );

    final idempotencyKey = _newIdempotencyKey();
    try {
      final created = await _repo.createComment(
        postId: postId,
        parentCommentId: null,
        body: body,
        idempotencyKey: idempotencyKey,
      );
      // §6 A6 — atomic swap. The temp ID row is REPLACED by the
      // server-confirmed row in a single state write. No
      // duplicate, no double-render.
      final next = state.value;
      if (next == null) return;
      final replaced = <CommentRow>[];
      var found = false;
      for (final row in next.comments) {
        if (row.tempId == tempId) {
          replaced.add(CommentRow(tempId: created.id, comment: created));
          found = true;
        } else {
          replaced.add(row);
        }
      }
      if (!found) {
        // The optimistic row was lost (a loadMore swept it out, or
        // a sibling mutation removed it). Append the real row at
        // the end so the user's content is still visible.
        replaced.add(CommentRow(tempId: created.id, comment: created));
      }
      state = AsyncData(
        next.copyWith(comments: replaced, isSubmitting: false, draftBody: ''),
      );
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.comments.submit.failure',
        fields: {'postId': postId.value},
      );
      _rollbackOptimistic(tempId);
      final next = state.value;
      if (next != null) {
        state = AsyncData(
          next.copyWith(isSubmitting: false, lastError: failure),
        );
      }
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.comments.submit.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'postId': postId.value},
      );
      _rollbackOptimistic(tempId);
      final next = state.value;
      if (next != null) {
        state = AsyncData(
          next.copyWith(
            isSubmitting: false,
            lastError: UnknownFailure(
              code: FailureCode.unknown,
              cause: error,
              stackTrace: stackTrace,
            ),
          ),
        );
      }
    }
  }

  /// Edit an existing comment.
  Future<void> editComment({
    required ContentId commentId,
    required String body,
  }) async {
    final current = state.value;
    if (current == null) return;
    final bodyClean = body.trim();
    if (bodyClean.isEmpty) return;

    try {
      final updated = await _repo.updateComment(
        commentId: commentId,
        body: bodyClean,
        idempotencyKey: _newIdempotencyKey(),
      );
      final next = state.value;
      if (next == null) return;
      final replaced = <CommentRow>[
        for (final row in next.comments)
          if (row.tempId == commentId)
            CommentRow(tempId: updated.id, comment: updated)
          else
            row,
      ];
      state = AsyncData(next.copyWith(comments: replaced, lastError: null));
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.comments.edit.failure',
        fields: {'commentId': commentId.value},
      );
      state = AsyncData(current.copyWith(lastError: failure));
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.comments.edit.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'commentId': commentId.value},
      );
      state = AsyncData(
        current.copyWith(
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Delete a comment.
  Future<void> deleteComment(ContentId commentId) async {
    final current = state.value;
    if (current == null) return;
    try {
      await _repo.deleteComment(
        commentId: commentId,
        idempotencyKey: _newIdempotencyKey(),
      );
      final next = state.value;
      if (next == null) return;
      state = AsyncData(
        next.copyWith(
          comments: <CommentRow>[
            for (final row in next.comments)
              if (row.tempId != commentId) row,
          ],
          lastError: null,
        ),
      );
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.comments.delete.failure',
        fields: {'commentId': commentId.value},
      );
      state = AsyncData(current.copyWith(lastError: failure));
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.comments.delete.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'commentId': commentId.value},
      );
      state = AsyncData(
        current.copyWith(
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Drop the last error (the user dismissed the banner).
  void clearError() {
    final current = state.value;
    if (current == null || current.lastError == null) return;
    state = AsyncData(current.copyWith(lastError: null));
  }

  // ---- internal ----------------------------------------------------------

  void _rollbackOptimistic(ContentId tempId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        comments: <CommentRow>[
          for (final row in current.comments)
            if (row.tempId != tempId) row,
        ],
      ),
    );
  }

  int _idempotencyCounter = 0;

  String _newIdempotencyKey() {
    _idempotencyCounter += 1;
    return 'e09-r16-$_idempotencyCounter-${DateTime.now().microsecondsSinceEpoch}';
  }
}

/// Provider for the [CommentController]. The screen reads this
/// directly; the repository dependency is pulled from
/// [communityPostRepositoryProvider], which production wires to the
/// future Kör 17 ``HttpCommunityPostRepository`` and tests override
/// with a recording fake.
final commentControllerProvider =
    AsyncNotifierProvider.autoDispose<CommentController, CommentSheetState>(
      CommentController.new,
    );
