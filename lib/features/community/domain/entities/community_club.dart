/// Community club (E09-R05, ADR 0399 §1, SDD §16).
///
/// A club is a topic-centric small Community, with its own member
/// roster, role hierarchy, visibility knob and pinned posts. Clubs
/// live in their own feature (Kör 24) but the Kör 5 profile / feed
/// surfaces reference them, so the entity lives here in the
/// Community domain.
library;

import '../value_objects/content_id.dart';
import '../value_objects/public_user_id.dart';

/// Three-state club visibility (SDD §16.2). `discoverable` lets
/// the club show up in club search but not on the public profile
/// surface.
enum ClubVisibility { private, discoverable, public }

/// Decode a wire-string into a [ClubVisibility]. Returns `null` for
/// unknown values (A3) — the data layer picks the safe fallback
/// (private).
ClubVisibility? clubVisibilityFromWire(String? wire) {
  if (wire == null || wire.isEmpty) return null;
  for (final visibility in ClubVisibility.values) {
    if (visibility.name == wire) return visibility;
  }
  return null;
}

/// The wire-string form for the given [ClubVisibility].
String clubVisibilityToWire(ClubVisibility visibility) => visibility.name;

/// The role a viewer has inside a club (SDD §16.3).
///
/// Roles are server-authoritative: the role used to author a post,
/// pin a thread or invite a member MUST come from this enum, never
/// from a user-supplied string.
enum ClubRole { owner, moderator, member }

/// Maximum documented size of a club roster (SDD §16.5 limit). The
/// server is the canonical enforcer; the value object emits a
/// structural bound so UI can pre-validate.
const int kCommunityClubMaxMembers = 500;

/// A Community club.
///
/// [memberCount] includes the owner. [myRole] is `null` iff the
/// viewer is NOT a member — non-members can still see `discoverable`
/// and `public` clubs per the visibility rules.
final class CommunityClub {
  factory CommunityClub({
    required ContentId id,
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required PublicUserId ownerId,
    required int memberCount,
    required ClubRole? myRole,
    required DateTime createdAt,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'club name must not be empty');
    }
    if (trimmed.length > 60) {
      throw ArgumentError.value(
        name,
        'name',
        'club name must be at most 60 characters',
      );
    }
    if (description.length > 2000) {
      throw ArgumentError.value(
        description,
        'description',
        'club description must be at most 2000 characters',
      );
    }
    if (tags.length > 10) {
      throw ArgumentError.value(tags, 'tags', 'a club has at most 10 tags');
    }
    for (final tag in tags) {
      if (tag.isEmpty || tag.length > 24) {
        throw ArgumentError.value(
          tags,
          'tags',
          'each tag must be 1-24 characters',
        );
      }
    }
    if (memberCount < 1) {
      throw ArgumentError.value(
        memberCount,
        'memberCount',
        'memberCount must be at least 1 (the owner)',
      );
    }
    if (memberCount > kCommunityClubMaxMembers) {
      throw ArgumentError.value(
        memberCount,
        'memberCount',
        'memberCount must be at most '
            '$kCommunityClubMaxMembers',
      );
    }
    return CommunityClub._(
      id: id,
      name: trimmed,
      description: description,
      visibility: visibility,
      tags: List<String>.unmodifiable(tags),
      ownerId: ownerId,
      memberCount: memberCount,
      myRole: myRole,
      createdAt: createdAt,
    );
  }

  const CommunityClub._({
    required this.id,
    required this.name,
    required this.description,
    required this.visibility,
    required this.tags,
    required this.ownerId,
    required this.memberCount,
    required this.myRole,
    required this.createdAt,
  });

  final ContentId id;
  final String name;
  final String description;
  final ClubVisibility visibility;
  final List<String> tags;
  final PublicUserId ownerId;
  final int memberCount;
  final ClubRole? myRole;
  final DateTime createdAt;

  CommunityClub copyWith({
    ContentId? id,
    String? name,
    String? description,
    ClubVisibility? visibility,
    List<String>? tags,
    PublicUserId? ownerId,
    int? memberCount,
    ClubRole? myRole,
    DateTime? createdAt,
  }) {
    return CommunityClub._(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      visibility: visibility ?? this.visibility,
      tags: tags ?? this.tags,
      ownerId: ownerId ?? this.ownerId,
      memberCount: memberCount ?? this.memberCount,
      myRole: myRole ?? this.myRole,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CommunityClub &&
      other.id == id &&
      other.name == name &&
      other.description == description &&
      other.visibility == visibility &&
      _sameList(other.tags, tags) &&
      other.ownerId == ownerId &&
      other.memberCount == memberCount &&
      other.myRole == myRole &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    visibility,
    Object.hashAll(tags),
    ownerId,
    memberCount,
    myRole,
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
