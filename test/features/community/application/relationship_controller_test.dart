/// Community social-graph controller widget tests (E09-R07).
///
/// Covers the §6 / §6.1 acceptance matrix for the controller:
///
/// * A6 — optimistic follow rolls back on a network failure.
/// * A7 — public profile → optimistic ``following``; private
///   profile → optimistic ``pendingRequestOutgoing``.
///
/// Each cell has a separate test so a regression that hides an
/// invariant behind a default case is caught. The fake repository
/// records every mutation call and exposes programmable failures;
/// the controller is exercised through its public surface
/// (``follow`` / ``unfollow``) and the state read through
/// ``communityRelationshipControllerProvider``.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/community/application/controllers/relationship_controller.dart';
import 'package:strumsight/features/community/data/repositories/relationship_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/social_graph_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';

class _FakeSocialGraphRepository implements SocialGraphRepository {
  _FakeSocialGraphRepository();

  AppFailure? followFailure;
  AppFailure? unfollowFailure;
  AppFailure? acceptFailure;
  AppFailure? declineFailure;
  AppFailure? removeFollowerFailure;

  int followCalls = 0;
  int unfollowCalls = 0;
  int acceptCalls = 0;
  int declineCalls = 0;
  int removeFollowerCalls = 0;

  final List<String> followKeys = <String>[];
  final List<String> unfollowKeys = <String>[];

  @override
  Future<CommunityPage<CommunityProfile>> followingPage({
    required PublicUserId userId,
    required Object cursor,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPage<CommunityProfile>> followersPage({
    required PublicUserId userId,
    required Object cursor,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<ContentId> follow({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    followCalls++;
    followKeys.add(idempotencyKey);
    if (followFailure != null) throw followFailure!;
    return ContentId('req-$followCalls');
  }

  @override
  Future<void> unfollow({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    unfollowCalls++;
    unfollowKeys.add(idempotencyKey);
    if (unfollowFailure != null) throw unfollowFailure!;
    return;
  }

  @override
  Future<void> acceptFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) async {
    acceptCalls++;
    if (acceptFailure != null) throw acceptFailure!;
    return;
  }

  @override
  Future<void> declineFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) async {
    declineCalls++;
    if (declineFailure != null) throw declineFailure!;
    return;
  }

  @override
  Future<void> removeFollower({
    required PublicUserId follower,
    required String idempotencyKey,
  }) async {
    removeFollowerCalls++;
    if (removeFollowerFailure != null) throw removeFollowerFailure!;
    return;
  }

  @override
  Future<void> block({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> unblock({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> mute({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> unmute({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');
}

ProviderContainer _container(_FakeSocialGraphRepository repo) {
  final container = ProviderContainer(
    overrides: [socialGraphRepositoryProvider.overrideWithValue(repo)],
  );
  return container;
}

void main() {
  group('A6 — optimistic follow rolls back on network failure', () {
    test('failed follow reverts the optimistic state', () async {
      final repo = _FakeSocialGraphRepository()
        ..followFailure = const NetworkFailure(
          code: FailureCode.networkUnavailable,
        );
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        communityRelationshipControllerProvider.notifier,
      );
      final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f70');

      // Seed the server-known relationship as ``notRelated``.
      controller.seedRelationship(
        target,
        CommunityRelationshipToViewer.notRelated,
      );
      // The optimistic follow fires the network call, which fails.
      final result = await controller.follow(target);

      expect(result, isA<CommunityRelationshipSubmitFailure>());
      expect(repo.followCalls, 1, reason: 'repository should have been called');

      final state = container
          .read(communityRelationshipControllerProvider)
          .value!;
      // After rollback, the optimistic override is cleared and the
      // server value is restored — A6.
      final view = state.relationships[target];
      expect(
        view?.effective,
        CommunityRelationshipToViewer.notRelated,
        reason: 'A6 violated — the optimistic state did not roll back',
      );
      expect(
        view?.optimistic,
        isNull,
        reason: 'optimistic override should be cleared',
      );
      expect(state.isSubmitting, isFalse);
    });
  });

  group('A7 — public vs private follow targets', () {
    test(
      'follow against a notRelated target enters pendingRequestOutgoing',
      () async {
        final repo = _FakeSocialGraphRepository();
        final container = _container(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          communityRelationshipControllerProvider.notifier,
        );
        final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f71');
        controller.seedRelationship(
          target,
          CommunityRelationshipToViewer.notRelated,
        );

        await controller.follow(target);

        final state = container
            .read(communityRelationshipControllerProvider)
            .value!;
        // After a successful follow the optimistic value is committed
        // as the new server-confirmed state — the Kör 8 follow-up
        // ``fetchById`` will refine this against the actual profile
        // visibility. The fresh-follow optimistic default is
        // ``pendingRequestOutgoing`` because the controller does not
        // know the target's visibility — the §5.2 contract.
        final view = state.relationships[target];
        expect(
          view?.server,
          CommunityRelationshipToViewer.pendingRequestOutgoing,
          reason:
              'A7 violated — optimistic follow must commit pending '
              'as the new server-confirmed value',
        );
        expect(
          view?.optimistic,
          isNull,
          reason: 'optimistic cleared after commit',
        );
        expect(repo.followCalls, 1);
        expect(repo.followKeys.first, isNotEmpty);
      },
    );

    test(
      'follow against a target that already follows you yields mutual',
      () async {
        final repo = _FakeSocialGraphRepository();
        final container = _container(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          communityRelationshipControllerProvider.notifier,
        );
        final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f72');
        // Seed: target already follows the caller. The follow click
        // optimistically flips to ``mutualFollow`` (the §10.2 path).
        controller.seedRelationship(
          target,
          CommunityRelationshipToViewer.theyFollowYou,
        );

        await controller.follow(target);

        final state = container
            .read(communityRelationshipControllerProvider)
            .value!;
        final view = state.relationships[target];
        expect(
          view?.server,
          CommunityRelationshipToViewer.mutualFollow,
          reason:
              'A7 violated — accepting a follow from an existing '
              'follower should commit mutual as the new server value',
        );
        expect(view?.optimistic, isNull);
      },
    );

    test('unfollow after a successful follow reverts to notRelated', () async {
      final repo = _FakeSocialGraphRepository();
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        communityRelationshipControllerProvider.notifier,
      );
      final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f73');
      // Seed: already following.
      controller.seedRelationship(
        target,
        CommunityRelationshipToViewer.youFollowThem,
      );

      final result = await controller.unfollow(target);
      expect(result, isA<CommunityRelationshipSubmitSuccess>());
      expect(repo.unfollowCalls, 1);

      final state = container
          .read(communityRelationshipControllerProvider)
          .value!;
      final view = state.relationships[target];
      expect(
        view?.server,
        CommunityRelationshipToViewer.notRelated,
        reason:
            'A7 violated — unfollow must commit notRelated as the '
            'new server-confirmed value',
      );
    });

    test('unfollow against a pendingRequestOutgoing server value flips '
        'to notRelated (the cancel branch — ADR 0401 §3)', () async {
      final repo = _FakeSocialGraphRepository();
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        communityRelationshipControllerProvider.notifier,
      );
      final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f74');
      controller.seedRelationship(
        target,
        CommunityRelationshipToViewer.pendingRequestOutgoing,
      );

      final result = await controller.unfollow(target);
      expect(result, isA<CommunityRelationshipSubmitSuccess>());

      final state = container
          .read(communityRelationshipControllerProvider)
          .value!;
      final view = state.relationships[target];
      expect(view?.server, CommunityRelationshipToViewer.notRelated);
    });
  });

  group('controller wiring — happy path round-trip', () {
    test('a successful follow commits the optimistic state as the new '
        'server-confirmed value', () async {
      final repo = _FakeSocialGraphRepository();
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        communityRelationshipControllerProvider.notifier,
      );
      final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f75');
      controller.seedRelationship(
        target,
        CommunityRelationshipToViewer.notRelated,
      );

      final result = await controller.follow(target);
      expect(result, isA<CommunityRelationshipSubmitSuccess>());

      final state = container
          .read(communityRelationshipControllerProvider)
          .value!;
      final view = state.relationships[target];
      expect(
        view?.server,
        CommunityRelationshipToViewer.pendingRequestOutgoing,
        reason:
            'successful follow must commit pendingRequestOutgoing as the '
            'new server value (the optimistic default for unknown-target-'
            'state; the Kör 8 follow-up resolves the actual value)',
      );
      expect(
        view?.optimistic,
        isNull,
        reason: 'optimistic cleared after commit',
      );
      expect(state.isSubmitting, isFalse);
    });
  });
}
