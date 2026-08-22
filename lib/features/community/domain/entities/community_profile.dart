/// Community profile view (E09-R05, ADR 0399 §1, SDD §8.4).
///
/// The boundary value object the Community feature shows for *any*
/// profile (own, viewer, public, summary). The repository hides the
/// access-policy detail (§5.2 backend invariant); the profile model
/// itself is the SAME shape for every viewer — what differs is what
/// the repository chooses to populate before construction
/// (e.g. private profiles have placeholder handle + null bio for a
/// blocked viewer, per ADR 0398 §4 SUMMARY).
///
/// All fields are immutable; the typed relationship snapshot
/// ([CommunityRelationshipToViewer]) is what the Kör 7 social-graph
/// repository returns, frozen into a single value object so the UI
/// layer never holds an out-of-date relationship.
library;

import '../policies/community_audience.dart';
import '../value_objects/community_handle.dart';
import '../value_objects/public_user_id.dart';

/// The viewer's relationship to the profile owner at the time the
/// profile was fetched. Server-authoritative — the Kör 8 follow /
/// block / mute state machine writes here.
///
/// The "blockedBy" variant is the rare mirror-image of "blocked":
/// the profile owner has blocked the viewer. Both halves enforce the
/// backend §5.2 "block always wins" invariant on the client too.
enum CommunityRelationshipToViewer {
  notRelated,
  youFollowThem,
  theyFollowYou,
  mutualFollow,
  pendingRequestOutgoing,
  pendingRequestIncoming,
  blocked,
  blockedBy,
}

/// A public Community profile, ready for display.
///
/// The [displayName] length, [bio] length and [skillInterests] /
/// [badges] list sizes are validated at construction; the profile is
/// the boundary the rest of the app reads, so any malformed field is
/// a structural violation detected here, not at the widget tree.
final class CommunityProfile {
  factory CommunityProfile({
    required PublicUserId userId,
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
    required String? avatarUrl,
    required String? bio,
    required List<String> skillInterests,
    required List<String> badges,
    required CommunityRelationshipToViewer relationship,
    required DateTime createdAt,
  }) {
    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'displayName must not be empty',
      );
    }
    if (trimmedName.length > 40) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'displayName must be at most 40 characters',
      );
    }
    if (bio != null && bio.length > 500) {
      throw ArgumentError.value(
        bio,
        'bio',
        'bio must be at most 500 characters',
      );
    }
    if (skillInterests.length > 16) {
      throw ArgumentError.value(
        skillInterests,
        'skillInterests',
        'skillInterests must be at most 16 entries',
      );
    }
    if (badges.length > 32) {
      throw ArgumentError.value(
        badges,
        'badges',
        'badges must be at most 32 entries',
      );
    }
    return CommunityProfile._(
      userId: userId,
      handle: handle,
      displayName: trimmedName,
      visibility: visibility,
      avatarUrl: avatarUrl,
      bio: bio,
      skillInterests: List<String>.unmodifiable(skillInterests),
      badges: List<String>.unmodifiable(badges),
      relationship: relationship,
      createdAt: createdAt,
    );
  }

  const CommunityProfile._({
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.visibility,
    required this.avatarUrl,
    required this.bio,
    required this.skillInterests,
    required this.badges,
    required this.relationship,
    required this.createdAt,
  });

  final PublicUserId userId;
  final CommunityHandle handle;
  final String displayName;
  final ProfileVisibility visibility;
  final String? avatarUrl;
  final String? bio;
  final List<String> skillInterests;
  final List<String> badges;
  final CommunityRelationshipToViewer relationship;
  final DateTime createdAt;

  CommunityProfile copyWith({
    PublicUserId? userId,
    CommunityHandle? handle,
    String? displayName,
    ProfileVisibility? visibility,
    String? avatarUrl,
    String? bio,
    List<String>? skillInterests,
    List<String>? badges,
    CommunityRelationshipToViewer? relationship,
    DateTime? createdAt,
  }) {
    return CommunityProfile._(
      userId: userId ?? this.userId,
      handle: handle ?? this.handle,
      displayName: displayName ?? this.displayName,
      visibility: visibility ?? this.visibility,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      skillInterests: skillInterests ?? this.skillInterests,
      badges: badges ?? this.badges,
      relationship: relationship ?? this.relationship,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CommunityProfile &&
      other.userId == userId &&
      other.handle == handle &&
      other.displayName == displayName &&
      other.visibility == visibility &&
      other.avatarUrl == avatarUrl &&
      other.bio == bio &&
      _sameList(other.skillInterests, skillInterests) &&
      _sameList(other.badges, badges) &&
      other.relationship == relationship &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    userId,
    handle,
    displayName,
    visibility,
    avatarUrl,
    bio,
    Object.hashAll(skillInterests),
    Object.hashAll(badges),
    relationship,
    createdAt,
  );
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
