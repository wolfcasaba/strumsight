/// Community challenge — definition + invite lifecycle (E09-R05,
/// ADR 0399 §1, SDD §15.2-§15.3).
///
/// A challenge is the *async* competitive surface — both definition
/// (what is being measured) and lifecycle (where the participant is
/// in the invite / completion timeline) live on the same entity
/// because the Kör 6+ feed query returns them together. The
/// definitions and the invite lifecycle live here as a single
/// immutable snapshot.
library;

import '../value_objects/content_id.dart';
import '../value_objects/public_user_id.dart';

/// The lifecycle of a single challenge invitee row (SDD §15.3).
///
/// Terminal states (`accepted` → `completed | forfeited | expired`;
/// `declined`; `cancelled`) never transition further. The
/// server-authoritative backend enforces the transition graph; this
/// enum is the Kör 5 vocabulary.
enum ChallengeInviteState {
  draft,
  sent,
  accepted,
  declined,
  expired,
  cancelled,
  active,
  completed,
  forfeited,
}

/// Decode a wire-string into a [ChallengeInviteState]. Returns `null`
/// for unknown values — the data layer's row-deserializer can
/// preserve the unknown state as a tombstone row instead of throwing
/// (A3).
ChallengeInviteState? challengeInviteStateFromWire(String? wire) {
  if (wire == null) return null;
  for (final state in ChallengeInviteState.values) {
    if (state.name == wire) return state;
  }
  return null;
}

/// The wire-string form for the given [ChallengeInviteState].
String challengeInviteStateToWire(ChallengeInviteState state) => state.name;

/// What kind of challenge this is (SDD §15.1).
enum ChallengeType {
  friends('friends'),
  club('club'),
  dailyCommunity('dailyCommunity'),
  periodicGlobal('periodicGlobal'),
  personalBest('personalBest');

  const ChallengeType(this.wireValue);

  final String wireValue;
}

/// Decode a wire-string into a [ChallengeType]. Returns `null` for
/// unknown values (A3). The Kör 16 leaderboard and the Kör 18 ranking
/// surface branch on this enum; an unknown type degrades the post to
/// a metadata-only row.
ChallengeType? challengeTypeFromWire(String? wire) {
  if (wire == null || wire.isEmpty) return null;
  for (final type in ChallengeType.values) {
    if (type.wireValue == wire) return type;
  }
  return null;
}

/// The wire-string form for the given [ChallengeType].
String challengeTypeToWire(ChallengeType type) => type.wireValue;

/// Minimum / maximum bounds for a challenge metric. The server is the
/// canonical validator; this value object is the structural bound.
const int kCommunityChallengeMetricMinValue = 0;
const int kCommunityChallengeMetricMaxValue = 1000000;

/// A challenge invitation row from the perspective of ONE viewer.
///
/// "Me" is implicit at the entity level — the repository returns one
/// of these per (challenge, viewer) pair, hydrated from Kör 16's
/// join. [inviteState] is server-authoritative; the optimistic UI
/// does NOT translate `accepted` → `active` locally, it waits for
/// the server to confirm.
final class CommunityChallengeParticipantState {
  factory CommunityChallengeParticipantState({
    required ContentId challengeId,
    required PublicUserId participantId,
    required ChallengeInviteState inviteState,
    required int? bestMetricValue,
  }) {
    if (bestMetricValue != null &&
        (bestMetricValue < kCommunityChallengeMetricMinValue ||
            bestMetricValue > kCommunityChallengeMetricMaxValue)) {
      throw ArgumentError.value(
        bestMetricValue,
        'bestMetricValue',
        'bestMetricValue must be in '
            '[$kCommunityChallengeMetricMinValue, '
            '$kCommunityChallengeMetricMaxValue]',
      );
    }
    return CommunityChallengeParticipantState._(
      challengeId: challengeId,
      participantId: participantId,
      inviteState: inviteState,
      bestMetricValue: bestMetricValue,
    );
  }

  const CommunityChallengeParticipantState._({
    required this.challengeId,
    required this.participantId,
    required this.inviteState,
    required this.bestMetricValue,
  });

  final ContentId challengeId;
  final PublicUserId participantId;
  final ChallengeInviteState inviteState;

  /// Personal best for this (challenge, participant), or `null`
  /// when the participant has not yet submitted a verified
  /// result (SDD §15.5).
  final int? bestMetricValue;

  CommunityChallengeParticipantState copyWith({
    ContentId? challengeId,
    PublicUserId? participantId,
    ChallengeInviteState? inviteState,
    int? bestMetricValue,
  }) {
    return CommunityChallengeParticipantState._(
      challengeId: challengeId ?? this.challengeId,
      participantId: participantId ?? this.participantId,
      inviteState: inviteState ?? this.inviteState,
      bestMetricValue: bestMetricValue ?? this.bestMetricValue,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CommunityChallengeParticipantState &&
      other.challengeId == challengeId &&
      other.participantId == participantId &&
      other.inviteState == inviteState &&
      other.bestMetricValue == bestMetricValue;

  @override
  int get hashCode =>
      Object.hash(challengeId, participantId, inviteState, bestMetricValue);
}

/// A full challenge definition.
///
/// [startsAt] / [endsAt] are the server's authoritative window; the
/// client refuses to submit results outside this window (Kör 16
/// server-side check is the security boundary). [metric] is a free
/// label string (e.g. "score", "durationSeconds") — defined enum in
/// Kör 15+.
final class CommunityChallengeDefinition {
  factory CommunityChallengeDefinition({
    required ContentId id,
    required int version,
    required ChallengeType type,
    required String metric,
    required int difficulty,
    required DateTime startsAt,
    required DateTime endsAt,
    required PublicUserId authorId,
    String? clubId,
  }) {
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'version must be positive');
    }
    if (difficulty < 1) {
      throw ArgumentError.value(
        difficulty,
        'difficulty',
        'difficulty must be positive',
      );
    }
    if (metric.isEmpty) {
      throw ArgumentError.value(metric, 'metric', 'metric must not be empty');
    }
    if (!endsAt.isAfter(startsAt)) {
      throw ArgumentError.value(
        endsAt,
        'endsAt',
        'endsAt must be after startsAt',
      );
    }
    return CommunityChallengeDefinition._(
      id: id,
      version: version,
      type: type,
      metric: metric,
      difficulty: difficulty,
      startsAt: startsAt,
      endsAt: endsAt,
      authorId: authorId,
      clubId: clubId,
    );
  }

  const CommunityChallengeDefinition._({
    required this.id,
    required this.version,
    required this.type,
    required this.metric,
    required this.difficulty,
    required this.startsAt,
    required this.endsAt,
    required this.authorId,
    required this.clubId,
  });

  final ContentId id;
  final int version;
  final ChallengeType type;
  final String metric;
  final int difficulty;
  final DateTime startsAt;
  final DateTime endsAt;
  final PublicUserId authorId;

  /// Nullable club affinity. Only present for [ChallengeType.club];
  /// Kör 24 will validate that this field is non-null precisely when
  /// the type is `club`.
  final String? clubId;

  CommunityChallengeDefinition copyWith({
    ContentId? id,
    int? version,
    ChallengeType? type,
    String? metric,
    int? difficulty,
    DateTime? startsAt,
    DateTime? endsAt,
    PublicUserId? authorId,
    String? clubId,
  }) {
    return CommunityChallengeDefinition._(
      id: id ?? this.id,
      version: version ?? this.version,
      type: type ?? this.type,
      metric: metric ?? this.metric,
      difficulty: difficulty ?? this.difficulty,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      authorId: authorId ?? this.authorId,
      clubId: clubId ?? this.clubId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CommunityChallengeDefinition &&
      other.id == id &&
      other.version == version &&
      other.type == type &&
      other.metric == metric &&
      other.difficulty == difficulty &&
      other.startsAt == startsAt &&
      other.endsAt == endsAt &&
      other.authorId == authorId &&
      other.clubId == clubId;

  @override
  int get hashCode => Object.hash(
    id,
    version,
    type,
    metric,
    difficulty,
    startsAt,
    endsAt,
    authorId,
    clubId,
  );
}
