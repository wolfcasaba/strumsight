/// Repository contract for Community challenges (E09-R05, ADR 0399
/// §1, SDD §15, §21.6).
///
/// Definitions, invites, results and leaderboard queries all live
/// here — the Kör 16 leaderboard and the Kör 18 ranking surface
/// both branch on the same definition data, and the §13.2 feed
/// embeds challenges together with posts.
library;

import '../entities/community_challenge.dart';
import '../value_objects/content_id.dart';
import '../value_objects/public_user_id.dart';
import 'community_page.dart';

abstract interface class CommunityChallengeRepository {
  /// Paged list of challenges visible to the viewer (Kör 16).
  /// Filters: window-state (`active|upcoming|ended`), club scope,
  /// and the access-policy block list.
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  });

  /// Fetch a single definition by id.
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  });

  /// Fetch the viewer's own participant state for [challengeId].
  /// Returns `null` when the viewer is not a participant.
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  });

  /// Invite a user to a challenge (SDD §15.3 invite lifecycle).
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  });

  /// Accept a pending invite.
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  });

  /// Decline a pending invite.
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  });

  /// Cancel an outgoing (draft / sent) invite. Owner / moderator
  /// only, enforced server-side.
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  });

  /// Submit a verified challenge result (SDD §15.5). Server enforces
  /// the window, the eligibility and the receipt signature; the
  /// client never sends a `verified: true` field.
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  });

  /// Paged leaderboard entries. The leaderboard is `verified`-only
  /// (SDD §15.5).
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  });
}
