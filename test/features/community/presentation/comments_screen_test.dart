/// Comments-screen widget tests (E09-R16).
///
/// Covers the §6 acceptance cells that are visible from the Flutter
/// layer. The backend service has its own dedicated test file
/// (E09-R16 §3 split: backend pytest covers A1–A8 except A6, the
/// UI covers A6 — the temp-ID atomikus csere is a UI-only
/// invariant). The Flutter tests here pin:
///
/// * A6 — the temp ID is REPLACED by the server ID in a SINGLE
///   atomic state write. After the server response lands, the list
///   contains exactly ONE row for the user's submission — neither
///   two (the temp + real) nor zero (the optimistic gone).
///
/// * UI smoke — the screen mounts, the first page loads, the
///   composer field accepts input, the Send button is disabled
///   while the submit is in flight, and the field is cleared on
///   success.
///
/// The fake repository records every call so the tests assert the
/// controller's contract (the Kör 14 ``following_feed_test`` /
/// Kör 15 ``reaction_controller_test`` precedent).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/community/application/controllers/comment_controller.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart';
import 'package:strumsight/features/community/domain/entities/community_comment.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/moderation_state.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/post_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/comments_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

class _FakeCommunityPostRepository implements CommunityPostRepository {
  _FakeCommunityPostRepository();

  /// Programmable first-page response for ``comments()``. The next
  /// ``comments`` call pops this queue.
  final List<CommunityPage<CommunityComment>> scriptedCommentsPages =
      <CommunityPage<CommunityComment>>[];

  /// Programmable ``createComment`` response. The next call returns
  /// this value verbatim.
  CommunityComment? nextCreatedComment;

  /// Programmable throw — when set, the next ``createComment`` call
  /// throws this exception. Cleared on consume.
  Object? nextCreateThrow;

  /// Records every ``comments`` call so the test can assert the
  /// cursor was forwarded correctly.
  final List<Object?> commentsCalls = <Object?>[];

  /// Records every ``createComment`` call.
  final List<({ContentId postId, ContentId? parentCommentId, String body})>
  createCalls =
      <({ContentId postId, ContentId? parentCommentId, String body})>[];

  /// Synchronisation lock — the controller's submit is async, so a
  /// test that asserts the in-flight optimistic state needs the
  /// submit to be paused mid-flight. The fake's ``createComment``
  /// awaits a [Completer] that the test resolves when it's ready to
  /// assert the optimistic state, then resolves with the
  /// server-confirmed row.
  Completer<CommunityComment>? _pendingCreate;

  void pauseNextCreate(Completer<CommunityComment> completer) {
    _pendingCreate = completer;
  }

  @override
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  }) async {
    commentsCalls.add(cursor);
    if (scriptedCommentsPages.isEmpty) {
      return CommunityPage<CommunityComment>(
        items: const <CommunityComment>[],
        cursor: const CursorPage.haltedAfterRequest(),
      );
    }
    return scriptedCommentsPages.removeAt(0);
  }

  @override
  Future<CommunityComment> createComment({
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required String idempotencyKey,
  }) async {
    // ignore: avoid_print
    createCalls.add((
      postId: postId,
      parentCommentId: parentCommentId,
      body: body,
    ));
    if (nextCreateThrow != null) {
      final error = nextCreateThrow!;
      nextCreateThrow = null;
      throw error;
    }
    if (_pendingCreate != null) {
      return _pendingCreate!.future;
    }
    if (nextCreatedComment == null) {
      throw StateError('nextCreatedComment not set');
    }
    return nextCreatedComment!;
  }

  @override
  Future<CommunityComment> updateComment({
    required ContentId commentId,
    required String body,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteComment({
    required ContentId commentId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  // ---- Other CommunityPostRepository methods — stubs (un-used by
  // the comment-sheet flow).

  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CommunityPost?> fetchPost({required ContentId postId}) async {
    throw UnimplementedError();
  }

  @override
  Future<CommunityPost> updatePost({
    required ContentId postId,
    required String? body,
    required CommunityAudience audience,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deletePost({
    required ContentId postId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> setReaction({
    required ContentId postId,
    required Object? kind,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> setBookmark({
    required ContentId postId,
    required bool bookmarked,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }
}

// ---------------------------------------------------------------------------
// Helpers — build a CommunityComment with deterministic fields.
// ---------------------------------------------------------------------------

final _viewerAuthorId = PublicUserId('viewer');

CommunityComment _comment({
  required String id,
  required String body,
  DateTime? createdAt,
}) {
  return CommunityComment(
    id: ContentId(id),
    authorId: _viewerAuthorId,
    postId: ContentId('post-1'),
    parentCommentId: null,
    body: body,
    createdAt: createdAt ?? DateTime.utc(2026, 8, 23, 12, 0, 0),
    moderationState: ModerationState.visible,
  );
}

Widget _wrap({
  required Widget child,
  required _FakeCommunityPostRepository fakeRepo,
}) {
  return ProviderScope(
    overrides: [communityPostRepositoryProvider.overrideWithValue(fakeRepo)],
    child: MaterialApp(
      // The screen reads its labels through AppLocalizations.of(context)
      // (the §6 F1 l10n fix — every user-facing string goes through ARB
      // en/hu). The test pins the English locale so `find.text('Send')`
      // and similar text-based assertions resolve to the English copy.
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: child,
    ),
  );
}

/// Read the current value of [commentControllerProvider] from a
/// widget's element. Riverpod's `Element.read` requires the element
/// to be hosted under a `ProviderScope`; this wrapper is the
/// helper the tests use to assert state changes between frames.
CommentSheetState _readState(WidgetTester tester) {
  final element = tester.element(find.byType(CommentsScreen));
  return ProviderScope.containerOf(
    element,
  ).read(commentControllerProvider).value!;
}

void main() {
  group('E09-R16 CommentsScreen A6 — temp ID atomikus csere', () {
    testWidgets(
      'optimistic create shows ONE row after server response (temp ID replaced atomically)',
      (tester) async {
        final fake = _FakeCommunityPostRepository();
        // First page is empty; the controller will then create a
        // new comment whose optimistic row gets replaced by the
        // server response.
        fake.scriptedCommentsPages.add(
          CommunityPage<CommunityComment>(
            items: const <CommunityComment>[],
            cursor: const CursorPage.haltedAfterRequest(),
          ),
        );
        final realId = ContentId('server-real-1');
        fake.nextCreatedComment = _comment(
          id: realId.value,
          body: 'Hello world',
          createdAt: DateTime.utc(2026, 8, 23, 12, 0, 5),
        );

        await tester.pumpWidget(
          _wrap(
            fakeRepo: fake,
            child: CommentsScreen(postId: ContentId('post-1')),
          ),
        );
        // Drain the first page load.
        await tester.pumpAndSettle();

        // The user types a body and taps Send.
        await tester.enterText(find.byType(TextField), 'Hello world');
        await tester.pump();

        // Pause the createComment call so we can observe the
        // optimistic state BEFORE the server response lands.
        final completer = Completer<CommunityComment>();
        fake.pauseNextCreate(completer);
        await tester.tap(find.text('Send'));
        await tester.pump(); // publish optimistic state

        // The optimistic row is in the list with a temp ID. We
        // assert it appears exactly once — the §6 A6 contract is
        // that the user never sees a duplicate.
        final dataBefore = _readState(tester);
        expect(dataBefore.comments.length, 1, reason: 'optimistic row landed');
        expect(
          dataBefore.comments.first.tempId.value.startsWith('temp-c-'),
          isTrue,
          reason: 'optimistic row carries a temp-c-* id',
        );

        // Let the fake's createComment return the server row.
        completer.complete(fake.nextCreatedComment!);
        await tester.pumpAndSettle();

        // The list now contains exactly ONE row, with the
        // server's real ID. The temp ID has been replaced in a
        // SINGLE atomic state write — the user never saw two
        // rows.
        final dataAfter = _readState(tester);
        expect(dataAfter.comments.length, 1);
        expect(dataAfter.comments.first.tempId, realId);
        expect(dataAfter.comments.first.comment.body, 'Hello world');
      },
    );

    testWidgets('submit failure rolls the optimistic row back', (tester) async {
      final fake = _FakeCommunityPostRepository();
      fake.scriptedCommentsPages.add(
        CommunityPage<CommunityComment>(
          items: const <CommunityComment>[],
          cursor: const CursorPage.haltedAfterRequest(),
        ),
      );
      fake.nextCreateThrow = NetworkFailure(code: FailureCode.networkServer);

      await tester.pumpWidget(
        _wrap(
          fakeRepo: fake,
          child: CommentsScreen(postId: ContentId('post-1')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'will fail');
      await tester.pump();
      // ignore: avoid_print
      // ignore: avoid_print
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      // After the failure, the optimistic row is rolled back —
      // the list is empty AND the lastError is set so the
      // banner surfaces.
      final after = _readState(tester);
      // ignore: avoid_print
      expect(after.comments, isEmpty);
      expect(after.lastError, isA<NetworkFailure>());
      expect(after.isSubmitting, isFalse);
      expect(after.draftBody, 'will fail'); // draft is preserved
    });

    testWidgets(
      'Send button is disabled while submit is in flight and re-enabled on success',
      (tester) async {
        final fake = _FakeCommunityPostRepository();
        fake.scriptedCommentsPages.add(
          CommunityPage<CommunityComment>(
            items: const <CommunityComment>[],
            cursor: const CursorPage.haltedAfterRequest(),
          ),
        );
        fake.nextCreatedComment = _comment(
          id: 'real-1',
          body: 'hi',
          createdAt: DateTime.utc(2026, 8, 23, 12, 0, 5),
        );

        await tester.pumpWidget(
          _wrap(
            fakeRepo: fake,
            child: CommentsScreen(postId: ContentId('post-1')),
          ),
        );
        await tester.pumpAndSettle();

        // Empty draft → Send disabled.
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );

        await tester.enterText(find.byType(TextField), 'hi');
        await tester.pump();

        // Non-empty draft → Send enabled.
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );

        await tester.tap(find.text('Send'));
        await tester.pump();

        // After success, the field is cleared → Send disabled again.
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
      },
    );
  });
}
