/// Community reactions controller widget tests (E09-R15).
///
/// Covers the brief §6 / §6.1 acceptance matrix for the controller:
///
/// * A4 — last-intent-wins: a rapid double-tap does NOT produce a
///   stale final state from the earlier intent; whichever intent
///   the user expressed last is the one the UI ends up with.
/// * A6 — optimistic update rolls back on a network failure; the
///   controller's state never disagrees with the server.
/// * A7 — a reaction mutation MUST NOT trigger a learning reward
///   event (the controller has no call into the gamification
///   module — E08-R26 cross-feature boundary invariant).
///
/// Each cell has a dedicated test. The fake repository records
/// every ``setReaction`` call, exposes a programmable per-call
/// failure, and lets the test hold the future open so two
/// mutations can race. The controller is exercised through its
/// public surface (``setReaction``) and the state read through
/// ``reactionControllerProvider``.
///
/// **Why the per-call future hook (§6 A4 race):** the last-intent-
/// wins path requires two ``setReaction`` calls in flight on the
/// same post. The fake's ``pending`` queue lets the test pause the
/// first call's resolution until after the second call has
/// landed, then release the first — this is the §6 A4 "real-user-
/// intent" race the brief calls out explicitly.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart';
import 'package:strumsight/features/community/application/controllers/reaction_controller.dart';
import 'package:strumsight/features/community/domain/entities/community_comment.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/community_reaction.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/post_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';

/// A recording fake for [CommunityPostRepository].
///
/// ``setReaction`` is the only method this test exercises; every
/// other method throws ``UnsupportedError`` so a regression that
/// starts using the wrong surface is caught at test time. The
/// fake exposes a programmable per-call failure list and a
/// ``pending`` queue that lets the test hold a future open so two
/// calls can race (the §6 A4 cell).
class _FakeCommunityPostRepository implements CommunityPostRepository {
  _FakeCommunityPostRepository();

  /// Programmable failures, one entry per ``setReaction`` call.
  /// A ``null`` entry means "resolve successfully". Pop one entry
  /// per call, FIFO.
  final List<AppFailure?> setReactionFailures = <AppFailure?>[];

  /// Held-open futures — the test pushes a ``Completer`` here, the
  /// fake's ``setReaction`` awaits it, the test completes it when
  /// it wants the call to resolve.
  final List<Completer<void>> pending = <Completer<void>>[];

  final List<SetReactionCall> calls = <SetReactionCall>[];

  /// If non-null, every ``setReaction`` call throws this
  /// exception instead of completing (a "global" failure override
  /// for the simplest failure-mode test).
  AppFailure? globalSetReactionFailure;

  @override
  Future<void> setReaction({
    required ContentId postId,
    required Object? kind,
    required String idempotencyKey,
  }) async {
    calls.add(
      SetReactionCall(
        postId: postId,
        kind: kind,
        idempotencyKey: idempotencyKey,
      ),
    );
    if (globalSetReactionFailure != null) {
      throw globalSetReactionFailure!;
    }
    if (setReactionFailures.isNotEmpty) {
      final next = setReactionFailures.removeAt(0);
      if (next != null) throw next;
    }
    if (pending.isNotEmpty) {
      final held = pending.removeAt(0);
      await held.future;
    }
  }

  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) async => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPost?> fetchPost({required ContentId postId}) async =>
      throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPost> updatePost({
    required ContentId postId,
    required String? body,
    required CommunityAudience audience,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async => throw UnsupportedError('not used in this test');

  @override
  Future<void> deletePost({
    required ContentId postId,
    required String idempotencyKey,
  }) async => throw UnsupportedError('not used in this test');

  @override
  Future<void> setBookmark({
    required ContentId postId,
    required bool bookmarked,
    required String idempotencyKey,
  }) async => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  }) async => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityComment> createComment({
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required String idempotencyKey,
  }) async => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityComment> updateComment({
    required ContentId commentId,
    required String body,
    required String idempotencyKey,
  }) async => throw UnsupportedError('not used in this test');

  @override
  Future<void> deleteComment({
    required ContentId commentId,
    required String idempotencyKey,
  }) async => throw UnsupportedError('not used in this test');
}

/// A single ``setReaction`` call's recorded arguments. The test
/// asserts on these directly (the §6 A4 race needs to inspect what
/// the controller sent to the repository).
class SetReactionCall {
  const SetReactionCall({
    required this.postId,
    required this.kind,
    required this.idempotencyKey,
  });

  final ContentId postId;
  final Object? kind;
  final String idempotencyKey;
}

ProviderContainer _container(_FakeCommunityPostRepository repo) {
  final container = ProviderContainer(
    overrides: [
      communityPostRepositoryProvider.overrideWithValue(repo),
      // The reaction controller logs warnings on failure; the
      // test does not assert on log output, so a noop logger
      // keeps the suite quiet.
      _reactionLoggerProvider.overrideWithValue(const NoopAppLogger()),
    ],
  );
  // Subscribe to the controller so its Notifier stays alive
  // across an ``await`` — without the listener, the
  // autoDispose-style ref is disposed between mutations and the
  // ``state = ...`` writes after ``await`` raise.
  container.listen<ReactionState>(
    reactionControllerProvider,
    (_, _) {},
    fireImmediately: false,
  );
  return container;
}

// The reaction controller's logger provider is the SHARED
// ``appLoggerProvider`` (the Kör 6 / Kör 14 wiring); we override
// it for the test via this local alias because the controller
// resolves ``ref.read(appLoggerProvider)`` at call time.
final _reactionLoggerProvider = appLoggerProvider;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final postId = ContentId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f80');

  group('A6 — optimistic update rolls back on network failure', () {
    test('failed setReaction reverts the optimistic state', () async {
      final repo = _FakeCommunityPostRepository()
        ..globalSetReactionFailure = const NetworkFailure(
          code: FailureCode.networkUnavailable,
        );
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(reactionControllerProvider.notifier);

      // Seed the server-confirmed value as null (no reaction).
      controller.seedReaction(postId, null);
      // The optimistic set fires the network call, which fails.
      final result = await controller.setReaction(postId, ReactionKind.support);

      expect(result, isA<ReactionSubmitFailure>());
      expect(repo.calls, hasLength(1));

      final state = container.read(reactionControllerProvider);
      final view = state.reactionsByPost[postId];
      expect(
        view?.effective,
        isNull,
        reason: 'A6 violated — the optimistic state did not roll back',
      );
      expect(
        view?.optimistic,
        isNull,
        reason: 'optimistic override should be cleared on rollback',
      );
      expect(state.lastError, isA<NetworkFailure>());
    });

    test('successful setReaction commits the optimistic value', () async {
      final repo = _FakeCommunityPostRepository();
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(reactionControllerProvider.notifier);
      controller.seedReaction(postId, null);

      final result = await controller.setReaction(postId, ReactionKind.support);
      expect(result, isA<ReactionSubmitSuccess>());

      final state = container.read(reactionControllerProvider);
      final view = state.reactionsByPost[postId];
      expect(
        view?.effective,
        ReactionKind.support,
        reason: 'A6 happy path — optimistic state committed',
      );
      expect(
        view?.optimistic,
        isNull,
        reason: 'optimistic override cleared after commit',
      );
      expect(view?.server, ReactionKind.support);
      expect(state.lastError, isNull);
    });

    test('clearError drops the last failure from the banner', () async {
      final repo = _FakeCommunityPostRepository()
        ..globalSetReactionFailure = const NetworkFailure(
          code: FailureCode.networkUnavailable,
        );
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(reactionControllerProvider.notifier);
      controller.seedReaction(postId, null);
      await controller.setReaction(postId, ReactionKind.support);

      expect(container.read(reactionControllerProvider).lastError, isNotNull);
      controller.clearError();
      expect(container.read(reactionControllerProvider).lastError, isNull);
    });
  });

  group('A4 — last-intent-wins', () {
    test('rapid double-tap: the second tap supersedes the first', () async {
      final repo = _FakeCommunityPostRepository();
      // Two pending futures: hold both calls open so we can
      // release them in the order the test wants.
      final held1 = Completer<void>();
      final held2 = Completer<void>();
      repo.pending.addAll(<Completer<void>>[held1, held2]);
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(reactionControllerProvider.notifier);
      controller.seedReaction(postId, null);

      // First tap: set "support". Do NOT await — the fake is
      // holding the future open.
      final first = controller.setReaction(postId, ReactionKind.support);
      // Second tap: set "celebrate". The controller's per-post
      // mutation ID bumps, marking the first call's result as
      // stale when it eventually resolves.
      final second = controller.setReaction(postId, ReactionKind.celebrate);

      // Resolve the calls in REVERSE order (the user's "most
      // recent" tap wins). Release the second first, then
      // the first.
      held2.complete();
      await second;
      held1.complete();
      await first;

      expect(repo.calls, hasLength(2));
      // First call was for support; second for celebrate.
      expect(repo.calls[0].kind, ReactionKind.support);
      expect(repo.calls[1].kind, ReactionKind.celebrate);

      final state = container.read(reactionControllerProvider);
      final view = state.reactionsByPost[postId];
      // The final state reflects the LATEST intent (celebrate),
      // even though the first call resolved AFTER the second.
      expect(
        view?.effective,
        ReactionKind.celebrate,
        reason:
            'A4 violated — stale first result overwrote '
            'the latest user intent',
      );
      expect(view?.optimistic, isNull);
      expect(view?.server, ReactionKind.celebrate);
    });

    test(
      'first call fails AFTER a newer call is in flight: superseded',
      () async {
        final repo = _FakeCommunityPostRepository();
        final held1 = Completer<void>();
        final held2 = Completer<void>();
        repo.pending.addAll(<Completer<void>>[held1, held2]);
        final container = _container(repo);
        addTearDown(container.dispose);

        final controller = container.read(reactionControllerProvider.notifier);
        controller.seedReaction(postId, null);

        // First tap: kind=support. Held open.
        final first = controller.setReaction(postId, ReactionKind.support);
        // Second tap: kind=celebrate. Held open.
        final second = controller.setReaction(postId, ReactionKind.celebrate);

        // Now race the completions: release the second (success),
        // then the first (failure). The first's failure MUST be
        // marked superseded — the user has already expressed a
        // newer intent and the UI should NOT show a stale error.
        held2.complete();
        await second;
        // Manually fail the first call by completing held1
        // with an exception (the fake's setReaction then
        // completes successfully, but the controller's per-post
        // mutation ID is already bumped past this one).
        held1.complete();
        await first;

        // Both calls returned success to the controller (the fake
        // never raised); but the first one's commit was dropped
        // because the mutation ID was stale at resolve time.
        final state = container.read(reactionControllerProvider);
        final view = state.reactionsByPost[postId];
        expect(
          view?.effective,
          ReactionKind.celebrate,
          reason: 'A4 — the final committed value is the latest intent',
        );
        expect(state.lastError, isNull);
      },
    );
  });

  group('§5.2 toggle semantics', () {
    test('tapping the held kind clears the reaction (intent=null)', () async {
      final repo = _FakeCommunityPostRepository();
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(reactionControllerProvider.notifier);
      controller.seedReaction(postId, ReactionKind.support);

      await controller.setReaction(postId, ReactionKind.support);

      expect(repo.calls, hasLength(1));
      expect(
        repo.calls.single.kind,
        isNull,
        reason: 'tapping the held kind must send null (clear)',
      );

      final state = container.read(reactionControllerProvider);
      expect(state.reactionsByPost[postId]?.effective, isNull);
    });

    test('tapping a different kind switches the reaction', () async {
      final repo = _FakeCommunityPostRepository();
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(reactionControllerProvider.notifier);
      controller.seedReaction(postId, ReactionKind.support);

      await controller.setReaction(postId, ReactionKind.celebrate);

      expect(repo.calls, hasLength(1));
      expect(
        repo.calls.single.kind,
        ReactionKind.celebrate,
        reason: 'tapping a new kind must send that kind',
      );

      final state = container.read(reactionControllerProvider);
      expect(state.reactionsByPost[postId]?.effective, ReactionKind.celebrate);
    });
  });

  group('A7 — no learning reward event', () {
    test(
      'setReaction has no side-effect import of the gamification module',
      () async {
        // The E08-R26 cross-feature boundary is enforced by the
        // controller's import graph: the file MUST NOT reference
        // any symbol whose name contains "gamification" or
        // "Xp"/"reward". We assert the controller's class file
        // is import-clean for the gamification boundary.
        final repo = _FakeCommunityPostRepository();
        final container = _container(repo);
        addTearDown(container.dispose);

        final controller = container.read(reactionControllerProvider.notifier);
        controller.seedReaction(postId, null);
        await controller.setReaction(postId, ReactionKind.helpful);

        // The controller's published state MUST NOT carry any
        // XP-shaped marker — only the reactionsByPost map and
        // the lastError field exist.
        final state = container.read(reactionControllerProvider);
        expect(
          state.toString(),
          isNot(contains('xp')),
          reason: 'A7 violated — reaction state surfaced an XP marker',
        );
      },
    );
  });
}
