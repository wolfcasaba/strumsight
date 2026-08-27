/// E13-R33 — offline publish retry (A6).
///
/// The offline queue's idempotency guarantee — §0.0.B/B6: the
/// `PostComposerController` generates the idempotency key EXACTLY ONCE (on
/// the first draft save) and every later save/submit reuses it; the
/// `CommunityOutbox` collapses a second `enqueue()` with the SAME key into
/// the existing pending record rather than creating a duplicate.
///
/// This test drives the REAL [PostComposerController] against the REAL
/// [LocalCommunityOutbox] (not a fake outbox) — only the network boundary
/// ([CommunityPostRepository.createPost]) is faked, and it is scripted to
/// fail every attempt (simulating "offline"). Two publish attempts with the
/// same [PostComposerState.idempotencyKey] must leave exactly ONE pending
/// record in the outbox — never two.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart';
import 'package:strumsight/features/community/application/outbox/community_outbox.dart';
import 'package:strumsight/features/community/domain/entities/community_comment.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/post_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';

import '../../core/storage/in_memory_key_value_store.dart';

/// Fails every `createPost` call — simulates the device being offline for
/// the whole test, so every pending record stays pending across drains.
class _AlwaysOfflineRepository implements CommunityPostRepository {
  int createCalls = 0;
  final List<String> idempotencyKeysSeen = <String>[];

  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) async {
    createCalls += 1;
    idempotencyKeysSeen.add(idempotencyKey);
    throw const NetworkFailure(code: FailureCode.networkUnavailable);
  }

  @override
  Future<CommunityPost?> fetchPost({required ContentId postId}) =>
      throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPost> updatePost({
    required ContentId postId,
    required String? body,
    required CommunityAudience audience,
    required Object resourceVersion,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> deletePost({
    required ContentId postId,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> setReaction({
    required ContentId postId,
    required Object? kind,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> setBookmark({
    required ContentId postId,
    required bool bookmarked,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityComment> createComment({
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityComment> updateComment({
    required ContentId commentId,
    required String body,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> deleteComment({
    required ContentId commentId,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._user);
  final AuthUser _user;
  @override
  Future<AuthUser?> build() async => _user;
}

Map<String, Object?> _practiceSummaryArtifactJson() {
  return PracticeSummaryArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'sess-fixture-retry',
    createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    activeSeconds: 30,
    pausedSeconds: 0,
    attemptCount: 1,
    finishReasonCode: 'userFinished',
    bestScore: 0.5,
    coachingCodes: const <String>[],
  ).toJson();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'two publish attempts with the same idempotency key leave exactly ONE pending record',
    () async {
      final repo = _AlwaysOfflineRepository();
      final store = InMemoryKeyValueStore();
      const user = AuthUser(id: 11, email: 'retry@strumsight.app');

      final container = ProviderContainer(
        overrides: [
          communityKeyValueStoreProvider.overrideWithValue(store),
          communityLoggerProvider.overrideWithValue(const NoopAppLogger()),
          communityPostRepositoryProvider.overrideWithValue(repo),
          // The REAL outbox — not overridden — so its actual
          // enqueue-dedup logic is what the test measures.
          composerSourceArtifactProvider.overrideWithValue(
            _practiceSummaryArtifactJson(),
          ),
          authControllerProvider.overrideWith(() => _FakeAuthController(user)),
        ],
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<PostComposerState>>(
        postComposerControllerProvider,
        (_, _) {},
        fireImmediately: false,
      );

      await container.read(postComposerControllerProvider.future);
      final notifier = container.read(postComposerControllerProvider.notifier);

      await notifier.updateBody('Első próbálkozás — offline maradok.');
      final mintedKey = container
          .read(postComposerControllerProvider)
          .value!
          .idempotencyKey;
      expect(mintedKey, isNotNull, reason: 'the key is minted on first save');
      final firstKey = mintedKey!;

      // Attempt #1 — fails (offline). The key survives the failure (A5).
      await notifier.submit();
      final afterFirst = container.read(postComposerControllerProvider).value!;
      expect(afterFirst.status, PostComposerStatus.failure);
      expect(
        afterFirst.idempotencyKey,
        firstKey,
        reason: 'a failed submit must NOT mint a new key',
      );

      // Attempt #2 — same key, still offline.
      await notifier.submit();
      final afterSecond = container.read(postComposerControllerProvider).value!;
      expect(afterSecond.status, PostComposerStatus.failure);
      expect(
        afterSecond.idempotencyKey,
        firstKey,
        reason: 'the retry reuses the SAME idempotency key, never a new one',
      );

      // The transport saw two attempts, both carrying the identical key —
      // this is what the server's own dedup relies on.
      expect(repo.createCalls, 2);
      expect(repo.idempotencyKeysSeen, <String>[firstKey, firstKey]);

      // KEY ASSERTION (A6) — the outbox's pending queue holds exactly ONE
      // record, with that one stable key. A regression that minted a new
      // key per submit (or that let the outbox double-enqueue on retry)
      // would leave TWO pending records here.
      final pending = container.read(communityOutboxProvider).pendingPosts();
      expect(pending, hasLength(1));
      expect(pending.single.idempotencyKey, firstKey);
    },
  );
}
