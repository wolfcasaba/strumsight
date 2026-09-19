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

/// A single verified-only leaderboard entry (E09-R23, ADR 0418 D1).
///
/// The leaderboard projection is verified-only (§A1 / §5.1), opt-in
/// (§A3 / §D2), and sorted by ``(metric_value DESC, submitted_at
/// ASC, id ASC)`` (§A2 / §D4). Every row carries a `verifiedBadge`
/// constant `true` by construction — the field exists so the wire
/// shape is forward-compatible with a future round that
/// distinguishes "verified" from "moderator-pinned".
///
/// This class lives COLOCATED with the ``CommunityChallengeRepository``
/// interface so the D1 "freezed on, signature fagyott" rule is
/// preserved — two test files outside this round's ``allowed_paths``
/// fake the interface and must keep compiling unchanged.
final class LeaderboardEntry {
  factory LeaderboardEntry({
    required PublicUserId publicId,
    required int rank,
    required String? displayName,
    required String? handle,
    required int metricValue,
    required DateTime submittedAt,
    required bool verifiedBadge,
  }) {
    if (rank < 1) {
      throw ArgumentError.value(rank, 'rank', 'rank must be positive');
    }
    return LeaderboardEntry._(
      publicId: publicId,
      rank: rank,
      displayName: displayName,
      handle: handle,
      metricValue: metricValue,
      submittedAt: submittedAt,
      verifiedBadge: verifiedBadge,
    );
  }

  const LeaderboardEntry._({
    required this.publicId,
    required this.rank,
    required this.displayName,
    required this.handle,
    required this.metricValue,
    required this.submittedAt,
    required this.verifiedBadge,
  });

  /// The participant's stable public user id (the wire surface).
  final PublicUserId publicId;

  /// The dense rank assigned at read time — the row's position in
  /// the projection (1-based, gaps when an excluded profile would
  /// have sat in between).
  final int rank;

  /// Display name, `null` for a profile that has not set one yet
  /// (the Kör 4 onboarding path is nullable). The Flutter screen
  /// falls back to `@handle` in that case.
  final String? displayName;

  /// @-prefixed handle from ``community_profiles.handle_display``,
  /// `null` for a profile that has not set one yet.
  final String? handle;

  /// The verified metric value (the §D3 / §D4 sort primary).
  final int metricValue;

  /// Server-authoritative submission timestamp (the §D4 sort
  /// secondary, ascending — earlier is better on a tie).
  final DateTime submittedAt;

  /// Always `true` for rows in the verified-only projection (§A1).
  /// The field exists for forward-compatibility with a future
  /// "moderator-pinned" extension.
  final bool verifiedBadge;

  @override
  bool operator ==(Object other) =>
      other is LeaderboardEntry &&
      other.publicId == publicId &&
      other.rank == rank &&
      other.displayName == displayName &&
      other.handle == handle &&
      other.metricValue == metricValue &&
      other.submittedAt == submittedAt &&
      other.verifiedBadge == verifiedBadge;

  @override
  int get hashCode => Object.hash(
    publicId,
    rank,
    displayName,
    handle,
    metricValue,
    submittedAt,
    verifiedBadge,
  );
}

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

/// A klub-hatókörű kihívás-olvasás — KÜLÖN szerződés, szándékosan
/// nem a [CommunityChallengeRepository] tizedik metódusa (WP-H4,
/// 2026-09-06).
///
/// **Miért külön.** A [CommunityChallengeRepository] docstringje
/// kimondja: „a D1 »freezed on, signature fagyott« szabály" — a
/// felületet KILENC teszt-fake implementálja (köztük a
/// `test/ui/goldens/**` alatti golden-fake-ek). Egy tizedik absztrakt
/// metódus mind a kilencet fordítási hibára vinné, holott a
/// klub-fülnek semmi köze a meghívás-életciklushoz. A külön interfész
/// ezt a csatolást szünteti meg: aki tudja, implementálja; aki nem,
/// az `is` teszten elbukik, és a hívó a „nem tudjuk" ágra megy —
/// pontosan úgy, ahogy a fül eddig is viselkedett.
///
/// **Miért nem lista, hanem oldal.** A szerver
/// (`GET /community/clubs/{public_id}/challenges`) lapozható
/// burkolót ad; a [CommunityPage] megőrzi a „vége" (`halted`) és a
/// „van még" (`continued`) különbséget, amit egy csupasz `List`
/// eldobna.
abstract interface class CommunityClubChallengeReader {
  /// A klub AKTÍV kihívásainak egy oldala.
  ///
  /// Dobás (nem üres oldal), ha a hívás nem elérhető vagy elszáll —
  /// az üres oldal ÁLLÍTÁS: „ennek a klubnak nincs aktív kihívása".
  Future<CommunityPage<CommunityChallengeDefinition>> clubChallenges({
    required ContentId clubId,
    required int limit,
  });
}
