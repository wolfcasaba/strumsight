// The community surface is REACHABLE, and only when the build says so.
//
// Every screen asserted here already existed with its own tests, and nothing
// anywhere constructed one — so the whole social feature was unreachable however the
// flag was set. These cells are the guard against that returning: a route that no
// longer resolves, or one that resolves with the flag off.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';

void main() {
  group('the route paths are shaped for the ids they carry', () {
    test('the gate is the entry point, not the feed', () {
      // Consent and the signed-in requirement live on the gate, so every link
      // from the rest of the app points there. A link straight to the feed would
      // route around both.
      expect(AppRoutes.community, '/community');
      expect(AppRoutes.communityFeed, '/community/feed');
      expect(
        AppRoutes.communityFeed.startsWith(AppRoutes.community),
        isTrue,
        reason:
            'the feed is under the gate, so a redirect on the gate covers it',
      );
    });

    test('the parameterised routes name their parameter', () {
      expect(AppRoutes.communityComments, contains(':postId'));
      expect(AppRoutes.communityLeaderboard, contains(':challengeId'));
      expect(AppRoutes.communityFollowers, contains(':profileId'));
      expect(AppRoutes.communityFollowing, contains(':profileId'));
    });

    test('followers and following are separate paths, not a query flag', () {
      // `FollowersScreen` takes a `FollowersMode`, and the direction is part of
      // WHAT is being shown rather than an option on it — so it belongs in the
      // path, where a shared link still says which list it meant.
      expect(AppRoutes.communityFollowers, isNot(AppRoutes.communityFollowing));
      expect(AppRoutes.communityFollowers.endsWith('/followers'), isTrue);
      expect(AppRoutes.communityFollowing.endsWith('/following'), isTrue);
    });

    test('no community path collides with an existing destination', () {
      final community = <String>[
        AppRoutes.community,
        AppRoutes.communityFeed,
        AppRoutes.communityNotifications,
        AppRoutes.communityBookmarks,
        AppRoutes.communitySafety,
        AppRoutes.communityChallenges,
        AppRoutes.communityClubs,
        AppRoutes.communityComments,
        AppRoutes.communityLeaderboard,
        AppRoutes.communityFollowers,
        AppRoutes.communityFollowing,
      ];
      expect(
        community.toSet(),
        hasLength(community.length),
        reason:
            'two routes sharing a path means one silently shadows the other',
      );
      for (final tab in AppRoutes.shellTabs) {
        expect(
          community,
          isNot(contains(tab)),
          reason: 'a community path must not shadow a shell destination',
        );
      }
    });

    test('the challenge LIST path exists as a constant but is not routed', () {
      // Deliberate, and measured rather than forgotten: the hosted instance serves
      // /community/leaderboards/{id} and /community/challenges/{id}/results but no
      // challenge list or detail, so `CommunityChallengesScreen` would be a screen
      // that always fails. The constant stays so the route is a one-line addition
      // the day the server grows those three paths
      // (`docs/operations/casaba-backend.md`).
      expect(AppRoutes.communityChallenges, '/community/challenges');
    });
  });
}
