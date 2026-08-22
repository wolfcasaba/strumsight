/// Community inbox notification item (E09-R05, ADR 0399 §1, SDD §17.1).
///
/// Each inbox item carries the notification kind, a localization key
/// for the title and body, and a read-marker. Per ARB rule (AGENTS.md
/// §7), user-facing strings live in the localization catalogues, NOT
/// in this entity — these are stable keys the Kör 6+ presentation
/// layer resolves via `AppLocalizations`.
library;

import '../value_objects/content_id.dart';

/// The Community notification kinds (SDD §17.1). Each maps 1:1 to a
/// server-routed event; a new event MUST land here so the inbox UI
/// can branch on a closed enum.
enum CommunityNotificationKind {
  followRequest('follow_request'),
  followAccepted('follow_accepted'),
  reactionSummary('reaction_summary'),
  comment('comment'),
  mention('mention'),
  challengeInvite('challenge_invite'),
  challengeCompleted('challenge_completed'),
  clubInvite('club_invite'),
  moderationDecision('moderation_decision'),
  securityAlert('security_alert');

  const CommunityNotificationKind(this.wireValue);

  final String wireValue;
}

/// Decode a wire-string into a [CommunityNotificationKind]. Returns
/// `null` for unknown values (A3). The inbox UI's "fall back to a
/// generic item" branch uses this.
CommunityNotificationKind? communityNotificationKindFromWire(String? wire) {
  if (wire == null || wire.isEmpty) return null;
  for (final kind in CommunityNotificationKind.values) {
    if (kind.wireValue == wire) return kind;
  }
  return null;
}

/// The wire-string form for the given [CommunityNotificationKind].
String communityNotificationKindToWire(CommunityNotificationKind kind) =>
    kind.wireValue;

/// A single notification row in the inbox.
///
/// Localization keys [titleKey] / [bodyKey] are stable lower-camel
/// keys (`'community_notification_challenge_invite_title'`, etc.) the
/// UI layer resolves via the ARB catalogues. The Kör 5 entity
/// validation only checks format, not that the key actually exists —
/// the latter is a CI / golden-test concern.
final class CommunityNotificationItem {
  factory CommunityNotificationItem({
    required ContentId id,
    required CommunityNotificationKind kind,
    required String titleKey,
    String? bodyKey,
    required DateTime createdAt,
    required bool isRead,
    ContentId? relatedContentId,
  }) {
    _requireLowerCamelCaseKey(titleKey, 'titleKey');
    if (bodyKey != null) {
      _requireLowerCamelCaseKey(bodyKey, 'bodyKey');
    }
    return CommunityNotificationItem._(
      id: id,
      kind: kind,
      titleKey: titleKey,
      bodyKey: bodyKey,
      createdAt: createdAt,
      isRead: isRead,
      relatedContentId: relatedContentId,
    );
  }

  const CommunityNotificationItem._({
    required this.id,
    required this.kind,
    required this.titleKey,
    required this.bodyKey,
    required this.createdAt,
    required this.isRead,
    required this.relatedContentId,
  });

  final ContentId id;
  final CommunityNotificationKind kind;
  final String titleKey;
  final String? bodyKey;
  final DateTime createdAt;
  final bool isRead;

  /// Optional pointer at the content this notification is about —
  /// e.g. a comment id, a challenge id or a moderation case id. The
  /// inbox tap-action reads this; `null` means the notification is
  /// purely informational (e.g. security alert).
  final ContentId? relatedContentId;

  CommunityNotificationItem copyWith({
    ContentId? id,
    CommunityNotificationKind? kind,
    String? titleKey,
    String? bodyKey,
    DateTime? createdAt,
    bool? isRead,
    ContentId? relatedContentId,
  }) {
    return CommunityNotificationItem._(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      titleKey: titleKey ?? this.titleKey,
      bodyKey: bodyKey ?? this.bodyKey,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      relatedContentId: relatedContentId ?? this.relatedContentId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CommunityNotificationItem &&
      other.id == id &&
      other.kind == kind &&
      other.titleKey == titleKey &&
      other.bodyKey == bodyKey &&
      other.createdAt == createdAt &&
      other.isRead == isRead &&
      other.relatedContentId == relatedContentId;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    titleKey,
    bodyKey,
    createdAt,
    isRead,
    relatedContentId,
  );
}

void _requireLowerCamelCaseKey(String value, String name) {
  if (!RegExp(r'^[a-z][A-Za-z0-9_]*$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a lowerCamelCase key');
  }
}
