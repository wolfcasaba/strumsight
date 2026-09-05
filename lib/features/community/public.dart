/// Public boundary of the Community feature (E09-R05, ADR 0399 §3,
/// SDD §6.1).
///
/// This barrel is the **only** entry point the rest of the app is
/// allowed to import from
/// (`package:strumsight/features/community/public.dart`). The domain
/// models, value objects and repository interfaces live in
/// `lib/features/community/domain/` and are re-exported here so the
/// cross-feature surface stays reviewable in a single file (the
/// pattern that ADR 0089/ADR 0339 lock in for the other feature
/// domains).
///
/// The Community domain is **framework-independent**: no Flutter,
/// Riverpod, Dio, SharedPreferences, l10n or storage plugin import is
/// allowed under this line. The `community domain stays framework-
/// free (E09-R05)` group in `architecture_dependency_test.dart`
/// enforces the rule at the round gate. The application and data
/// layers (Kör 6+) will gain their own barrels once they exist.
library;

// Wire-enum contracts (Kör 4 — imported, not redefined per ADR 0399 §4
// decision: the single source of truth for these enums lives in
// `policies/community_audience.dart`).
export 'domain/policies/community_audience.dart';

// Value objects — the structural, validated boundary types.
export 'domain/value_objects/audience.dart';
export 'domain/value_objects/community_handle.dart';
export 'domain/value_objects/content_id.dart';
export 'domain/value_objects/cursor_page.dart';
export 'domain/value_objects/public_user_id.dart';

// Entities — the public domain model.
export 'domain/entities/community_challenge.dart';
export 'domain/entities/community_club.dart';
export 'domain/entities/community_comment.dart';
export 'domain/entities/community_post.dart';
export 'domain/entities/community_profile.dart';
export 'domain/entities/community_reaction.dart';
export 'domain/entities/moderation_state.dart';
export 'domain/entities/notification_item.dart';

// Repository contracts — the cross-feature interface surface. The
// concrete Dio implementations land in Kör 6 and live in their own
// `data/` subfolder, NOT exported here.
export 'domain/repositories/challenge_repository.dart';
export 'domain/repositories/club_repository.dart';
export 'domain/repositories/community_page.dart';
export 'domain/repositories/community_profile_repository.dart';
export 'domain/repositories/feed_repository.dart';
export 'domain/repositories/notification_repository.dart';
export 'domain/repositories/post_repository.dart';
export 'domain/repositories/social_graph_repository.dart';

// ---------------------------------------------------------------------------
// Presentation — a route-olható képernyők (2026-09-05).
//
// Az `architecture_dependency_test.dart` „community is reachable only through
// public.dart" szabálya miatt a routernek IDE kell nyúlnia: a képernyők
// közvetlen importálása a `lib/features/community/presentation/...` útvonalról
// a gate-en elbukna. A fenti „framework-free" szabály KIZÁRÓLAG a
// `domain/` alkönyvtárra vonatkozik (a teszt azt a könyvtárat járja be), a
// presentation-réteg természetesen Fluttert használ.
// ---------------------------------------------------------------------------
export 'presentation/screens/bookmarks_screen.dart' show BookmarksScreen;
export 'presentation/screens/clubs/club_detail_screen.dart'
    show ClubDetailScreen;
export 'presentation/screens/clubs/club_list_screen.dart' show ClubListScreen;
export 'presentation/screens/comments_screen.dart' show CommentsScreen;
export 'presentation/screens/community_challenges_screen.dart'
    show CommunityChallengesScreen;
export 'presentation/screens/community_gate_screen.dart'
    show CommunityGateScreen;
export 'presentation/screens/community_notifications_screen.dart'
    show CommunityNotificationsScreen;
export 'presentation/screens/community_search_screen.dart'
    show CommunitySearchScreen;
export 'presentation/screens/followers_screen.dart'
    show FollowersMode, FollowersScreen;
export 'presentation/screens/following_feed_screen.dart'
    show FollowingFeedScreen;
export 'presentation/screens/leaderboard_screen.dart' show LeaderboardScreen;
export 'presentation/screens/post_composer_screen.dart'
    show PostComposerScreen;
export 'presentation/screens/safety_relationships_screen.dart'
    show SafetyRelationshipsScreen;
