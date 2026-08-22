/// Repository contract for Community clubs (E09-R05, ADR 0399 §1,
/// SDD §16, §21.7).
///
/// All club CRUD, membership and invitation lifecycle goes through
/// this single repository; the server-side permission matrix
/// (SDD §16.3 owner/moderator/member) is enforced on the backend
/// and never re-derived here.
library;

import '../entities/community_club.dart';
import '../value_objects/content_id.dart';
import '../value_objects/public_user_id.dart';
import 'community_page.dart';

abstract interface class CommunityClubRepository {
  /// Paged list of clubs visible to the viewer (combines the
  /// visibility filter — `private` only for members, `discoverable`
  /// for search; `public` for everyone).
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  });

  /// Fetch a single club by id; visibility-aware (returns a SUMMARY
  /// placeholder for non-members of a private club).
  Future<CommunityClub> fetchClub({required ContentId clubId});

  /// Create a new club. The caller becomes `owner` of the new
  /// club, the visibility defaults to `private` per the SDD §9.2
  /// privacy-first stance.
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  });

  /// Patch the mutable fields of a club — owner only.
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  });

  /// Request to join a club; the server converts this to a member
  /// row when the club's policy allows (Kör 24).
  Future<void> requestJoin({
    required ContentId clubId,
    required String idempotencyKey,
  });

  /// Invite [target] to join the club — owner or moderator only.
  Future<void> invite({
    required ContentId clubId,
    required PublicUserId target,
    required String idempotencyKey,
  });

  /// Leave the club voluntarily. The viewer must NOT be the only
  /// owner — the server enforces the ownership-transfer step.
  Future<void> leave({
    required ContentId clubId,
    required String idempotencyKey,
  });

  /// Remove a member — owner or moderator only. The owner's removal
  /// by themselves is rejected by the backend.
  Future<void> removeMember({
    required ContentId clubId,
    required PublicUserId memberId,
    required String idempotencyKey,
  });

  /// Transfer ownership to [newOwnerId]. Existing `owner` becomes a
  /// plain `member`. Documented in SDD §16.4 ownership transfer.
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  });
}
