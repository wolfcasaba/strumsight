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
///
/// The F3 group (§F3 fix) wires a real ``HttpSocialGraphRepository``
/// against a recording ``HttpClientAdapter`` so the test asserts
/// the URL the repository actually puts on the wire — not the
/// ``AppResult`` it returns. The pre-fix repository dropped the
/// ``?idempotency_key=`` query parameter; this test would have
/// caught it.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
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

  // ---------------------------------------------------------------------
  // F3 — DELETE /community/profiles/{id}/follow[ers/...] MUST carry the
  // idempotency_key as a query parameter (ADR 0401 §1). The pre-fix
  // repository dropped it; the backend would have answered 422 every
  // unfollow / remove-follower round-trip. The tests below wire a real
  // ``HttpSocialGraphRepository`` against a recording ``HttpClientAdapter``
  // and assert the URL the repository actually puts on the wire — not
  // the ``AppResult`` it returns, which is what the controller tests
  // above (intentionally) decouple from.
  // ---------------------------------------------------------------------

  group('F3 — DELETE URLs carry the idempotency_key query parameter', () {
    /// Scripted adapter: each call pops the next canned response in
    /// order; every request is recorded so the test can assert the
    /// path AND queryParameters Dio resolved for it.
    late List<RequestOptions> capturedRequests;
    late List<String> cannedBodies;
    late List<int> cannedStatuses;

    HttpClientAdapter buildAdapter() {
      capturedRequests = <RequestOptions>[];
      cannedBodies = <String>[];
      cannedStatuses = <int>[];
      return _ScriptedAdapter(
        onFetch: (options) {
          capturedRequests.add(options);
          // Default: empty 200 — the F3 path does not inspect the body.
          if (cannedBodies.isEmpty) {
            return _CannedResponse(body: '{}', status: 200);
          }
          return _CannedResponse(
            body: cannedBodies.removeAt(0),
            status: cannedStatuses.removeAt(0),
          );
        },
      );
    }

    HttpSocialGraphRepository buildRepo(HttpClientAdapter adapter) {
      final dio = Dio()..httpClientAdapter = adapter;
      return HttpSocialGraphRepository(ApiClient(dio));
    }

    test('unfollow() sends ?idempotency_key=... as a query parameter', () async {
      final repo = buildRepo(buildAdapter());
      final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f90');
      final key = 'unfollow-key-42';

      await repo.unfollow(
        target: target,
        idempotencyKey: key,
      );

      expect(capturedRequests, hasLength(1));
      final options = capturedRequests.single;
      // The repository builds the URL with the query string INLINE;
      // Dio preserves that and exposes the parsed query through
      // ``options.uri.queryParameters`` (it does NOT split it back
      // out into ``options.queryParameters`` when the call site
      // passes the query inline). Asserting the full path keeps
      // the test honest: a regression that dropped ``?key=...``
      // would be visible here.
      expect(
        options.path,
        '/community/profiles/${target.value}/follow'
        '?idempotency_key=$key',
        reason: 'F3 violated — DELETE URL path is wrong',
      );
      expect(
        options.uri.queryParameters['idempotency_key'],
        key,
        reason:
            'F3 violated — idempotency_key missing from query '
            'parameters (backend would answer 422)',
      );
      expect(options.method, 'DELETE');
    });

    test(
      'removeFollower() sends ?idempotency_key=... as a query parameter',
      () async {
        final adapter = buildAdapter();
        // First call is ``GET /community/profiles/me`` to resolve the
        // caller's own public-id (the Kör 7 contract documented on
        // ``_resolveCallerPublicId``). Second is the DELETE itself.
        cannedBodies
          ..add('{"public_id":"01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f91"}')
          ..add('{}');
        cannedStatuses..add(200)..add(200);

        final repo = buildRepo(adapter);
        final follower = PublicUserId(
          '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f92',
        );
        final key = 'remove-follower-key-99';

        await repo.removeFollower(
          follower: follower,
          idempotencyKey: key,
        );

        expect(capturedRequests, hasLength(2));
        final meCall = capturedRequests[0];
        final deleteCall = capturedRequests[1];

        expect(meCall.path, '/community/profiles/me');
        expect(meCall.method, 'GET');

        expect(
          deleteCall.path,
          '/community/profiles/'
          '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f91'
          '/followers/${follower.value}'
          '?idempotency_key=$key',
          reason: 'F3 violated — removeFollower DELETE URL path is wrong',
        );
        expect(
          deleteCall.uri.queryParameters['idempotency_key'],
          key,
          reason:
              'F3 violated — idempotency_key missing from '
              'removeFollower query parameters',
        );
        expect(deleteCall.method, 'DELETE');
      },
    );

    test('idempotency_key is encoded for HTTP (spaces / special chars)',
        () async {
      final repo = buildRepo(buildAdapter());
      final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f93');
      // The repository uses ``Uri.encodeQueryComponent`` on the key,
      // so a key with reserved characters round-trips intact through
      // the wire — the backend's ``min_length=1`` accepts anything
      // non-empty, but a key with ``&`` or ``+`` MUST NOT corrupt
      // the query string.
      final key = 'k ey+&';

      await repo.unfollow(target: target, idempotencyKey: key);

      final options = capturedRequests.single;
      expect(
        options.uri.queryParameters['idempotency_key'],
        key,
        reason:
            'F3 violated — the encoded idempotency_key did not '
            'decode back to its original value (Uri.encodeQueryComponent '
            'must be applied)',
      );
    });
  });
}

/// Canned adapter response — body + status.
class _CannedResponse {
  const _CannedResponse({required this.body, required this.status});
  final String body;
  final int status;
}

/// Records every request it sees and returns a scripted response.
/// Used by the F3 group to assert the URL ``HttpSocialGraphRepository``
/// actually puts on the wire.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({required this.onFetch});

  final _CannedResponse Function(RequestOptions options) onFetch;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final canned = onFetch(options);
    return ResponseBody.fromString(
      canned.body,
      canned.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
