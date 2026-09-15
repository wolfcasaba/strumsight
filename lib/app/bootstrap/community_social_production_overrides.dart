import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../core/logging/app_logger.dart';
import '../../core/storage/key_value_store.dart';
import '../../features/community/public.dart';

/// The Community SOCIAL seam providers the production `ProviderScope`
/// must wire — the sibling of `buildCommunityProductionOverrides`
/// (`community_production_overrides.dart`), which covers the feed /
/// post / composer side.
///
/// E18-R19 routed the notifications inbox and the club list, and the
/// challenge list is reachable from the inbox (this round); their data
/// seams stayed the test-only defaults, each throwing `StateError`
/// ("must be overridden in production wiring"): Riverpod folds the
/// throw into the reading controller's / `FutureProvider`'s error
/// state, so on a device the inbox and the club list rendered their
/// error card with no console exception (the E18-R01 finding F5
/// defect class, `docs/LESSONS.md` L652). Every widget test overrode
/// the seams, so the suite was blind.
///
/// What each override binds:
///
/// * `communityNotificationRepositoryProvider`
///   (`notification_controller.dart`) → `HttpCommunityNotificationRepository`
///   over the shared `accountApiClientProvider` (JWT + base URL in one
///   place); the disabled stand-in when the account layer is off.
///   NOTE: the backend has the inbox service but no notifications
///   router yet (measured 2026-09-15) — the calls are coded against
///   the route shape the service implies and surface a typed
///   `NetworkFailure` until it lands; see the impl's library comment.
/// * `communityChallengeRepositoryProvider` (`challenge_controller.dart`
///   — the seam `ChallengeController` and `community_challenges_screen`
///   read; NOT the same-named provider in `challenge_repository_impl.dart`,
///   which resolves the HTTP impl on its own and which the leaderboard
///   screen reads) → `HttpCommunityChallengeRepository`.
/// * `communityChallengeResultRepositoryProvider`
///   (`challenge_result_controller.dart`) → the same challenge impl —
///   the result-submission controller reads its own seam.
/// * `communityClubRepositoryProvider` (`club_list_screen.dart`, read by
///   the list / detail / member-management screens) →
///   `HttpCommunityClubRepository`.
/// * `socialGraphRepositoryProvider` (`relationship_repository_impl.dart`)
///   already resolves `HttpSocialGraphRepository` on its own, but that
///   implementation drops the cursor + limit on the two follow-list
///   reads (never sent — `ApiClient.getJson` takes no query map), so
///   "load more" on the followers / following screens re-fetches page
///   one. The override binds the cursor-forwarding decorator
///   `HttpCommunitySocialGraphRepository` from
///   `social_graph_repository_impl.dart`.
///
/// Every override resolves the account client through `ref.watch`, so
/// the repositories rebuild on every session change exactly as the
/// self-resolving providers do. No auth / session value is taken as a
/// parameter — the feed builder's decision, mirrored: the profile
/// implementation and the four impls wired here read the account
/// client through the provider graph, so the caller only supplies what
/// exists before the container does.
///
/// [keyValueStore] is accepted for parity with the feed builder (one
/// dependency set for both builders at the `main.dart` call site);
/// none of the four social repositories persists anything locally
/// today, so it is not bound to a provider here — the feed builder
/// already binds `communityKeyValueStoreProvider`, and a second
/// override of the same provider in one scope would be rejected.
/// [logger] reaches the notification impl (it reports rows with an
/// unknown wire kind that the decoder drops).
List<Override> buildCommunitySocialProductionOverrides({
  required KeyValueStore keyValueStore,
  required AppLogger logger,
}) {
  return <Override>[
    communityNotificationRepositoryProvider.overrideWith(
      (ref) => createCommunityNotificationRepository(
        ref.watch(communityNotificationApiClientProvider),
        logger: logger,
      ),
    ),
    communityChallengeRepositoryProvider.overrideWith(
      (ref) => createCommunityChallengeRepository(
        ref.watch(communityChallengeApiClientProvider),
      ),
    ),
    communityChallengeResultRepositoryProvider.overrideWith(
      (ref) => createCommunityChallengeRepository(
        ref.watch(communityChallengeApiClientProvider),
      ),
    ),
    communityClubRepositoryProvider.overrideWith(
      (ref) => createCommunityClubRepository(
        ref.watch(communityClubApiClientProvider),
      ),
    ),
    socialGraphRepositoryProvider.overrideWith(
      (ref) => createCommunitySocialGraphRepository(
        ref.watch(communitySocialApiClientProvider),
      ),
    ),
  ];
}
