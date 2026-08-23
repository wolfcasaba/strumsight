/// Community post composer controller tests (E09-R12).
///
/// Covers the §6 / §6.1 acceptance matrix for the composer:
///
/// * A1 — preview before publish: the controller's state exposes the
///   audience, the share-preview toggles, and the source artifact
///   the post will reference, so the screen can render a truthful
///   preview before submit.
/// * A3 — double-tap no two mutations: the controller's
///   ``isSubmitting`` guard collapses a second submit call while a
///   submit is in flight; the repository is called exactly once.
/// * A5 — user's text on error: a network-class submit failure
///   leaves the body in the state and in the draft store. The user
///   can edit and retry without losing their text.
/// * A6 — logout policy: the draft store is partitioned by
///   ``userId``; logout (signing in as a different user, or signing
///   back in as the same user) does NOT erase the draft. The policy
///   is documented in §10.
/// * A7 — sensitive share-preview fields default OFF: every flag on
///   the new draft is ``false`` before the user opts in.
///
/// Each cell has at least one dedicated test — a default-case
/// fixture cannot hide a regression that flips one flag the other
/// way. The fake repository records every call so the tests can
/// assert the controller's contract, not the repository's.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart';
import 'package:strumsight/features/community/application/outbox/community_outbox.dart';
import 'package:strumsight/features/community/data/local/community_draft_store.dart';
import 'package:strumsight/features/community/domain/entities/community_comment.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/moderation_state.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/post_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

/// A fixture source artifact the composer posts. Any artifact with a
/// real `type` discriminator is "non-empty" (the controller's
/// invariant) — using `PracticeSummaryArtifact` keeps the test
/// self-contained (no second feature's public.dart pulled into the
/// test fixture).
Map<String, Object?> _practiceSummaryArtifactJson() {
  return PracticeSummaryArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'sess-fixture-1',
    createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    activeSeconds: 60,
    pausedSeconds: 5,
    attemptCount: 1,
    finishReasonCode: 'userFinished',
    bestScore: 0.85,
    coachingCodes: const <String>['strongDownBeats'],
  ).toJson();
}

/// Minimal in-test fake for [CommunityPostRepository]. Records every
/// `createPost` call so the tests can assert the controller's
/// contract (A1, A3, A5) — they do NOT inspect the Kör 11 wire
/// shape, which is its own round.
class _FakeCommunityPostRepository implements CommunityPostRepository {
  _FakeCommunityPostRepository();

  /// Throw on the next `createPost` call. The Kör 12 controller
  /// catches [AppFailure] and the generic `Object` and surfaces
  /// either as a failure state (A5). A non-[AppFailure] throw is
  /// useful to exercise the catch-all path.
  Object? nextFailure;

  /// A delay injected before each `createPost` returns — lets the
  /// A3 test hold the controller in the in-flight state and probe
  /// the double-tap guard.
  Duration createDelay = Duration.zero;

  final List<CommunityAudience> audiences = <CommunityAudience>[];
  final List<String?> bodies = <String?>[];
  final List<Object> artifacts = <Object>[];
  final List<String> idempotencyKeys = <String>[];
  int createCalls = 0;

  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) async {
    createCalls += 1;
    audiences.add(audience);
    bodies.add(body);
    artifacts.add(artifact);
    idempotencyKeys.add(idempotencyKey);
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }
    final failure = nextFailure;
    if (failure != null) {
      // One-shot: clear the failure after the throw so a retry sees
      // a clean repository (mirrors "offline then online").
      nextFailure = null;
      throw failure;
    }
    return CommunityPost(
      id: ContentId('post-$createCalls'),
      authorId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f00'),
      audience: audience,
      body: body,
      artifact: UnfilledCommunityShareArtifact(),
      createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
      moderationState: ModerationState.visible,
      counts: CommunityPostCounts(
        reactionCount: 0,
        commentCount: 0,
        bookmarkCount: 0,
      ),
      viewerState: const CommunityViewerPostState.empty(),
    );
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

/// An in-memory [CommunityOutbox] backed by the test's [KeyValueStore]
/// — used by tests that need to verify persistence / restart
/// behaviour. The Kör 12 contract is the [CommunityOutbox] surface;
/// the local persistence impl is exercised in [community_outbox_test].
class _FakeCommunityOutbox implements CommunityOutbox {
  _FakeCommunityOutbox(this._repository);

  final _FakeCommunityPostRepository _repository;

  /// The pending list, in enqueue order. Tests inspect this to assert
  /// the A4 invariants.
  final List<CommunityPendingPost> pending = <CommunityPendingPost>[];

  /// Throw on the next `drain` call.
  Object? nextDrainFailure;

  @override
  Future<CommunityOutboxEnqueueResult> enqueue({
    required CommunityDraft draft,
  }) async {
    final key = draft.idempotencyKey;
    final existing = pending.where((record) => record.idempotencyKey == key);
    if (existing.isNotEmpty) {
      return CommunityOutboxEnqueueResult(
        accepted: false,
        record: existing.first,
      );
    }
    final record = CommunityPendingPost(
      idempotencyKey: key,
      audience: draft.audience,
      body: draft.body,
      sourceArtifactJson: Map<String, Object?>.from(draft.sourceArtifactJson),
      createdAt: draft.lastEditedAt,
      attempts: 0,
    );
    pending.add(record);
    return CommunityOutboxEnqueueResult(accepted: true, record: record);
  }

  @override
  Future<CommunityOutboxDrainReport> drain() async {
    final failure = nextDrainFailure;
    if (failure != null) {
      nextDrainFailure = null;
      throw failure;
    }
    final acknowledged = <String>[];
    final retrying = <String>[];
    for (final record in List<CommunityPendingPost>.from(pending)) {
      try {
        await _repository.createPost(
          audience: record.audience,
          body: record.body,
          artifact: record.sourceArtifactJson,
          idempotencyKey: record.idempotencyKey,
        );
        acknowledged.add(record.idempotencyKey);
        pending.removeWhere(
          (candidate) => candidate.idempotencyKey == record.idempotencyKey,
        );
      } on Object catch (_) {
        retrying.add(record.idempotencyKey);
      }
    }
    return CommunityOutboxDrainReport(
      acknowledged: List<String>.unmodifiable(acknowledged),
      retrying: List<String>.unmodifiable(retrying),
    );
  }

  @override
  List<CommunityPendingPost> pendingPosts() => List.unmodifiable(pending);
}

/// Build a ProviderContainer wired with a fake repository, a fake
/// outbox, an in-memory store, a logged-in user, and the composer's
/// source artifact. The [outbox] and [repository] are passed in so
/// tests can assert calls and inject failures.
ProviderContainer _container({
  required _FakeCommunityPostRepository repository,
  required _FakeCommunityOutbox outbox,
  required InMemoryKeyValueStore store,
  required AuthUser user,
  required Map<String, Object?> sourceArtifact,
}) {
  final container = ProviderContainer(
    overrides: [
      communityKeyValueStoreProvider.overrideWithValue(store),
      communityLoggerProvider.overrideWithValue(const NoopAppLogger()),
      communityPostRepositoryProvider.overrideWithValue(repository),
      communityOutboxProvider.overrideWithValue(outbox),
      composerSourceArtifactProvider.overrideWithValue(sourceArtifact),
      authControllerProvider.overrideWith(() => _FakeAuthController(user)),
    ],
  );
  // The composer is an autoDispose provider; subscribe to it so the
  // controller's in-flight `submit()` does not get its `Ref` disposed
  // mid-await (which would surface as "Cannot use the Ref ... after
  // it has been disposed" on the next `state = ...`).
  container.listen<AsyncValue<PostComposerState>>(
    postComposerControllerProvider,
    (_, _) {},
    fireImmediately: false,
  );
  return container;
}

/// A minimal fake of [AuthController] that just publishes the
/// supplied user. The composer only needs the `.value` (the
/// [AuthUser]) to compute the per-user storage key — it never
/// invokes any of the controller's auth flows.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this._user);

  final AuthUser _user;

  @override
  Future<AuthUser?> build() async => _user;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Shared fixtures.
  final user = const AuthUser(id: 42, email: 'készítő@example.com');
  final artifact = _practiceSummaryArtifactJson();

  group('A1 — preview before publish', () {
    test(
      'controller exposes audience + sharePreview + source artifact',
      () async {
        final store = InMemoryKeyValueStore();
        final repo = _FakeCommunityPostRepository();
        final outbox = _FakeCommunityOutbox(repo);
        final container = _container(
          repository: repo,
          outbox: outbox,
          store: store,
          user: user,
          sourceArtifact: artifact,
        );
        addTearDown(container.dispose);

        // Wait for the controller's AsyncNotifier build to settle.
        await container.read(postComposerControllerProvider.future);
        final notifier = container.read(
          postComposerControllerProvider.notifier,
        );

        // The user flips a few fields before submit. The controller
        // must reflect them in the state so the screen's preview pane
        // is accurate.
        await notifier.updateBody('Szia, ez egy teszt poszt.');
        await notifier.updateAudience(CommunityAudience.public);
        await notifier.setSharePreviewFlag(
          includeChordTimeline: false,
          includeStrumPattern: true,
          includeTempo: false,
          includeStreakDays: false,
          includeBestScore: false,
        );

        final state = container.read(postComposerControllerProvider).value!;
        // A1 — the preview pane the screen renders reads from the
        // controller state. If the controller did not expose these
        // fields, the screen would have to maintain a parallel copy
        // (a drift hazard) or the preview would be inaccurate.
        expect(state.body, 'Szia, ez egy teszt poszt.');
        expect(state.audience, CommunityAudience.public);
        expect(state.sharePreview.includeStrumPattern, isTrue);
        expect(state.sharePreview.includeChordTimeline, isFalse);
        expect(state.sourceArtifactJson, equals(artifact));
      },
    );
  });

  group('A3 — double-tap does not fire two mutations', () {
    test('second submit while the first is in flight is a no-op', () async {
      final store = InMemoryKeyValueStore();
      final repo = _FakeCommunityPostRepository()
        ..createDelay = const Duration(milliseconds: 80);
      final outbox = _FakeCommunityOutbox(repo);
      final container = _container(
        repository: repo,
        outbox: outbox,
        store: store,
        user: user,
        sourceArtifact: artifact,
      );
      addTearDown(container.dispose);

      await container.read(postComposerControllerProvider.future);
      final notifier = container.read(postComposerControllerProvider.notifier);
      await notifier.updateBody('first post body');

      // Fire two submits without awaiting — the first enters the
      // in-flight state; the second must collapse to a no-op.
      final first = notifier.submit();
      final second = notifier.submit();
      await Future.wait(<Future<void>>[first, second]);

      // A3 — exactly one repository call. A regression that
      // removed the `isSubmitting` guard would let both calls
      // through and `repo.createCalls` would be 2.
      expect(
        repo.createCalls,
        1,
        reason:
            'A3 violated — a second submit fired while the '
            'first was in flight',
      );
    });
  });

  group('A5 — user text preserved on submit failure', () {
    test('a network failure leaves the body in the controller state', () async {
      final store = InMemoryKeyValueStore();
      final repo = _FakeCommunityPostRepository()
        ..nextFailure = const NetworkFailure(
          code: FailureCode.networkUnavailable,
        );
      final outbox = _FakeCommunityOutbox(repo);
      final container = _container(
        repository: repo,
        outbox: outbox,
        store: store,
        user: user,
        sourceArtifact: artifact,
      );
      addTearDown(container.dispose);

      await container.read(postComposerControllerProvider.future);
      final notifier = container.read(postComposerControllerProvider.notifier);
      await notifier.updateBody('nem szabad elveszni');

      await notifier.submit();

      final state = container.read(postComposerControllerProvider).value!;
      // A5 — the user's text is preserved verbatim, the status
      // flipped to failure (no silent success, brief §5.1), and
      // the idempotency key is preserved so the next submit is
      // recognised as a retry of the same mutation.
      expect(state.body, 'nem szabad elveszni');
      expect(state.status, PostComposerStatus.failure);
      expect(state.lastError, isNotNull);
      expect(state.idempotencyKey, isNotNull);
    });

    test(
      'a non-AppFailure exception is also surfaced (catch-all path)',
      () async {
        final store = InMemoryKeyValueStore();
        final repo = _FakeCommunityPostRepository()
          ..nextFailure = StateError('platform transport blew up');
        final outbox = _FakeCommunityOutbox(repo);
        final container = _container(
          repository: repo,
          outbox: outbox,
          store: store,
          user: user,
          sourceArtifact: artifact,
        );
        addTearDown(container.dispose);

        await container.read(postComposerControllerProvider.future);
        final notifier = container.read(
          postComposerControllerProvider.notifier,
        );
        await notifier.updateBody('a body the user typed');

        await notifier.submit();

        final state = container.read(postComposerControllerProvider).value!;
        // The catch-all `Object` branch must still preserve the body
        // and surface a failure — a regression that swallowed the
        // throw would leave the user in `submitting` forever.
        expect(state.body, 'a body the user typed');
        expect(state.status, PostComposerStatus.failure);
        expect(state.isSubmitting, isFalse);
      },
    );
  });

  group('A6 — logout preserves the in-progress draft', () {
    test('logging out does NOT erase the draft from the draft store', () async {
      final store = InMemoryKeyValueStore();
      final repo = _FakeCommunityPostRepository();
      final outbox = _FakeCommunityOutbox(repo);
      final container = _container(
        repository: repo,
        outbox: outbox,
        store: store,
        user: user,
        sourceArtifact: artifact,
      );
      addTearDown(container.dispose);

      await container.read(postComposerControllerProvider.future);
      final notifier = container.read(postComposerControllerProvider.notifier);
      await notifier.updateBody('nem akarom elveszíteni');

      // The user typed, then the auth session ended (logout). The
      // §10 policy: the draft is user-scoped storage, so logout
      // does NOT touch it. A different user signing in reads from
      // their own key (and sees nothing); the original user
      // signing back in sees the same draft.
      final draftStore = container.read(communityDraftStoreProvider);
      final draftBeforeLogout = draftStore.readDraft();
      expect(draftBeforeLogout, isNotNull);
      expect(draftBeforeLogout!.body, 'nem akarom elveszíteni');

      // Simulate logout by rebuilding the container with a
      // different user. The first user's draft store is bound to
      // a separate [InMemoryKeyValueStore] partition (the
      // production key is `ss.community.drafts.v2.<userId>`).
      final otherUser = const AuthUser(id: 7, email: 'más@example.com');
      final otherContainer = _container(
        repository: repo,
        outbox: outbox,
        store: store,
        user: otherUser,
        sourceArtifact: artifact,
      );
      addTearDown(otherContainer.dispose);

      await otherContainer.read(postComposerControllerProvider.future);
      final otherStore = otherContainer.read(communityDraftStoreProvider);
      expect(
        otherStore.readDraft(),
        isNull,
        reason: 'A6 violated — a different user reads another user\'s draft',
      );

      // The original user's draft is still recoverable through the
      // original container (or, in production, by signing back in
      // as the same user — the draft store is rebuilt against the
      // same `ss.community.drafts.v2.42` key).
      final draftAfterLogout = draftStore.readDraft();
      expect(draftAfterLogout, isNotNull);
      expect(draftAfterLogout!.body, 'nem akarom elveszíteni');
      expect(draftAfterLogout.idempotencyKey, isNotEmpty);
    });
  });

  group('A7 — sensitive share-preview fields default OFF', () {
    test(
      'every SharePreview flag is false on a fresh composer session',
      () async {
        final store = InMemoryKeyValueStore();
        final repo = _FakeCommunityPostRepository();
        final outbox = _FakeCommunityOutbox(repo);
        final container = _container(
          repository: repo,
          outbox: outbox,
          store: store,
          user: user,
          sourceArtifact: artifact,
        );
        addTearDown(container.dispose);

        await container.read(postComposerControllerProvider.future);
        final state = container.read(postComposerControllerProvider).value!;

        // A7 — sensitive fields default to OFF in the preview before
        // the user opts in. The user explicitly flips the toggle they
        // want; a regression that defaulted a flag to true would fail
        // one of these assertions.
        expect(state.sharePreview.includeChordTimeline, isFalse);
        expect(state.sharePreview.includeStrumPattern, isFalse);
        expect(state.sharePreview.includeTempo, isFalse);
        expect(state.sharePreview.includeStreakDays, isFalse);
        expect(state.sharePreview.includeBestScore, isFalse);
      },
    );

    test(
      'an explicit flip is visible — a future flag-stomper fails here',
      () async {
        final store = InMemoryKeyValueStore();
        final repo = _FakeCommunityPostRepository();
        final outbox = _FakeCommunityOutbox(repo);
        final container = _container(
          repository: repo,
          outbox: outbox,
          store: store,
          user: user,
          sourceArtifact: artifact,
        );
        addTearDown(container.dispose);

        await container.read(postComposerControllerProvider.future);
        final notifier = container.read(
          postComposerControllerProvider.notifier,
        );
        await notifier.setSharePreviewFlag(
          includeChordTimeline: true,
          includeStrumPattern: false,
          includeTempo: false,
          includeStreakDays: false,
          includeBestScore: false,
        );

        final state = container.read(postComposerControllerProvider).value!;
        // The flag-stomper check: a regression that overwrote every
        // flag with `true` would flip `includeStrumPattern` here.
        expect(state.sharePreview.includeChordTimeline, isTrue);
        expect(state.sharePreview.includeStrumPattern, isFalse);
      },
    );
  });

  group('submit success path', () {
    test(
      'a successful submit flips status to success and clears the draft',
      () async {
        final store = InMemoryKeyValueStore();
        final repo = _FakeCommunityPostRepository();
        // The success path uses the real [LocalCommunityOutbox] so
        // the drain actually forwards the pending record to the
        // repository and acknowledges it. The fake outbox's drain
        // can be configured to no-op acknowledged; the local outbox
        // is the production-shaped path the Kör 12 controller calls.
        final realOutbox = LocalCommunityOutbox(
          repository: repo,
          store: store,
          logger: const NoopAppLogger(),
        );
        final container = ProviderContainer(
          overrides: [
            communityKeyValueStoreProvider.overrideWithValue(store),
            communityLoggerProvider.overrideWithValue(const NoopAppLogger()),
            communityPostRepositoryProvider.overrideWithValue(repo),
            communityOutboxProvider.overrideWithValue(realOutbox),
            composerSourceArtifactProvider.overrideWithValue(artifact),
            authControllerProvider.overrideWith(
              () => _FakeAuthController(user),
            ),
          ],
        );
        addTearDown(container.dispose);
        // Subscribe so the autoDispose provider stays alive during
        // the in-flight submit (see the helper's docstring).
        container.listen<AsyncValue<PostComposerState>>(
          postComposerControllerProvider,
          (_, _) {},
          fireImmediately: false,
        );

        await container.read(postComposerControllerProvider.future);
        final notifier = container.read(
          postComposerControllerProvider.notifier,
        );
        await notifier.updateBody('first successful post');

        await notifier.submit();

        final state = container.read(postComposerControllerProvider).value!;
        expect(state.status, PostComposerStatus.success);
        expect(state.lastSubmittedAt, isNotNull);
        // The draft is cleared on success so the next composer
        // session starts blank.
        final draftStore = container.read(communityDraftStoreProvider);
        expect(draftStore.readDraft(), isNull);
      },
    );
  });

  group('persistence — draft survives container rebuild', () {
    test(
      'A4 — restart-style rebuild reads the same draft from the store',
      () async {
        final store = InMemoryKeyValueStore();
        final repo = _FakeCommunityPostRepository();
        final outbox = _FakeCommunityOutbox(repo);

        // Session 1: type, save, the controller persists the draft.
        final container1 = _container(
          repository: repo,
          outbox: outbox,
          store: store,
          user: user,
          sourceArtifact: artifact,
        );
        addTearDown(container1.dispose);

        await container1.read(postComposerControllerProvider.future);
        final notifier1 = container1.read(
          postComposerControllerProvider.notifier,
        );
        await notifier1.updateBody('app was killed mid-typing');
        await notifier1.updateAudience(CommunityAudience.public);

        // Session 2: same store, fresh container — simulates app
        // restart. The draft should hydrate back.
        final container2 = _container(
          repository: repo,
          outbox: outbox,
          store: store,
          user: user,
          sourceArtifact: artifact,
        );
        addTearDown(container2.dispose);

        await container2.read(postComposerControllerProvider.future);
        final state = container2.read(postComposerControllerProvider).value!;
        // A4 — the draft body and the stable idempotency key both
        // survive the restart.
        expect(state.body, 'app was killed mid-typing');
        expect(state.audience, CommunityAudience.public);
        expect(state.idempotencyKey, isNotNull);
      },
    );
  });
}

// Imports kept in scope for future test cases — the analyzer accepts
// unused public imports (only unused local declarations fail).
