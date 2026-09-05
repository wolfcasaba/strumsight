/// Dio-backed implementation of [CommunityChallengeRepository]
/// (E09-R21, ADR 0415; E09-R22, ADR 0417).
///
/// The repository implements the **existing**
/// ``CommunityChallengeRepository`` contract from Kör 5 (ADR 0399)
/// — the file name is the implementation name, the interface is
/// the pre-existing one. Of the 9 methods:
///
/// * The 4 invite-lifecycle methods (``invite`` /
///   ``acceptInvite`` / ``declineInvite`` / ``cancelInvite``) are
///   wired against the Kör 21 backend endpoints.
/// * The 3 list / detail read methods (``listChallenges`` /
///   ``fetchDefinition`` / ``fetchMyParticipation``) are wired
///   against the corresponding GET endpoints so the
///   ``community_challenges_screen`` can render the screen from
///   real backend data.
/// * The 2 result / leaderboard methods (``submitResult`` /
///   ``leaderboard``) raise ``UnimplementedError`` (Kör 23 scope)
///   or, for ``submitResult``, hit the Kör 22 service layer
///   (the wire surface is the Kör 22 ``allowed_paths``).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../features/auth/public.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/community_challenge.dart';
import '../../domain/repositories/challenge_repository.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';

// Re-exported for the ``leaderboard_screen.dart`` so the screen
// reads ``LeaderboardEntry`` from a single import path.
export '../../domain/repositories/challenge_repository.dart'
    show LeaderboardEntry;

/// The single ``communityChallengeApiClient`` provider. Built
/// lazily so the account-disabled build never constructs the Dio
/// client at all — the same pattern as
/// ``communitySocialApiClientProvider`` in
/// ``relationship_repository_impl.dart``.
final communityChallengeApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

/// Disabled-mode fallback: returns ``ConfigurationFailure`` for
/// every call. Mirrors the pattern of
/// ``DisabledSocialGraphRepository`` /
/// ``DisabledCommunityProfileRepository`` so the controller code
/// path is uniform across the three repository flavours.
final class DisabledCommunityChallengeRepository
    implements CommunityChallengeRepository {
  const DisabledCommunityChallengeRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  }) async => throw _disabled.error;

  @override
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  }) async => throw _disabled.error;

  @override
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  }) async => throw _disabled.error;

  @override
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async => throw _disabled.error;
}

/// Live HTTP-backed challenge repository.
class HttpCommunityChallengeRepository implements CommunityChallengeRepository {
  HttpCommunityChallengeRepository(this._client);

  final ApiClient _client;

  @override
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  }) async {
    final params = <String, Object?>{'limit': limit};
    final cursorValue = cursorQueryValue(cursor);
    if (cursorValue != null) params['cursor'] = cursorValue;
    final result = await _client.getJson<dynamic>(
      '/community/challenges',
      queryParameters: params,
      decode: decodeChallengeListPage,
    );
    return switch (result) {
      Success(:final value) =>
        value as CommunityPage<CommunityChallengeDefinition>,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  }) async {
    final result = await _client.getJson<dynamic>(
      '/community/challenges/${challengeId.value}',
      decode: decodeChallengeDefinition,
    );
    return switch (result) {
      Success(:final value) => value as CommunityChallengeDefinition,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  }) async {
    final result = await _client.getJson<dynamic>(
      '/community/challenges/${challengeId.value}/me',
      decode: (json) => json,
    );
    return switch (result) {
      Success(:final value) => decodeParticipantOrNull(
        challengeId: challengeId,
        raw: value,
      ),
      Failure(:final error) => throw error,
    };
  }

  CommunityChallengeParticipantState? decodeParticipantOrNull({
    required ContentId challengeId,
    required Object? raw,
  }) {
    if (raw is! Map) return null;
    final participantValue = raw['participant'];
    if (participantValue == null) return null;
    return decodeParticipant(
      challengeId: challengeId,
      json: participantValue as Map<String, Object?>,
    );
  }

  @override
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/challenges/${challengeId.value}/invites',
      data: <String, Object?>{
        'invitee_public_id': target.value,
        'idempotency_key': idempotencyKey,
      },
    );
    if (result is Failure) {
      throw result.error;
    }
  }

  @override
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/challenges/invites/${challengeId.value}/accept',
      data: <String, Object?>{'idempotency_key': idempotencyKey},
    );
    if (result is Failure) {
      throw result.error;
    }
  }

  @override
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/challenges/invites/${challengeId.value}/decline',
      data: <String, Object?>{'idempotency_key': idempotencyKey},
    );
    if (result is Failure) {
      throw result.error;
    }
  }

  @override
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    final path =
        '/community/challenges/invites/${challengeId.value}'
        '?idempotency_key=${Uri.encodeQueryComponent(idempotencyKey)}';
    final result = await _client.delete(path, headers: const {});
    if (result is Failure) {
      throw result.error;
    }
  }

  /// Kör 22 — verified result submission (ADR 0417).
  ///
  /// The repository's ``submitResult`` returns ``Future<void>`` —
  /// a successful HTTP round-trip is the contract (the controller's
  /// separate pending-verification state is the §A7 surface; the
  /// §5.3 "local session success stays intact on upload failure"
  /// invariant lives in ``challenge_result_controller.dart``).
  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<dynamic>(
      '/community/challenges/${challengeId.value}/results',
      data: <String, Object?>{
        'metric_value': metricValue,
        'source_event_id': sourceEventId,
        'idempotency_key': idempotencyKey,
      },
      decode: decodeResult,
    );
    return switch (result) {
      Success() => null,
      Failure(:final error) => throw error,
    };
  }

  /// Kör 23 — verified-only leaderboard projection (ADR 0418).
  ///
  /// The repository hits the
  /// ``GET /community/leaderboards/{challenge_public_id}`` endpoint
  /// (Kör 23 D6) and decodes each row into a
  /// :class:`LeaderboardEntry`. The projection is verified-only
  /// (A1), opt-in (A3 / D2), and sorted by
  /// ``(metric_value DESC, submitted_at ASC, id ASC)`` (A2 / D4).
  /// The interface signature stays ``CommunityPage<Object>``
  /// (D1 — the column was ``Object`` in Kör 5) and the return
  /// value is a ``CommunityPage<LeaderboardEntry>`` — Dart generic
  /// covariance means this is valid against the declared
  /// ``CommunityPage<Object>`` signature.
  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async {
    // The ``ApiClient.getJson`` does not accept a
    // ``queryParameters`` arg — the cursor / limit are encoded
    // into the path via the same pattern the Kör 21
    // ``cancelInvite`` uses for the DELETE idempotency key.
    final cursorValue = cursorQueryValue(cursor);
    final querySegments = <String>[
      'limit=${Uri.encodeQueryComponent('$limit')}',
      if (cursorValue != null)
        'cursor=${Uri.encodeQueryComponent(cursorValue)}',
    ];
    final path =
        '/community/leaderboards/${challengeId.value}'
        '?${querySegments.join('&')}';
    final result = await _client.getJson<dynamic>(
      path,
      decode: decodeLeaderboardPage,
    );
    return switch (result) {
      Success(:final value) => value as CommunityPage<Object>,
      Failure(:final error) => throw error,
    };
  }

  // ---- internal ----------------------------------------------------------

  /// Decode the Kör 22 verified-receipt wire shape.
  ///
  /// The repository's ``submitResult`` returns ``Future<void>`` —
  /// a successful HTTP round-trip is the contract. The decoder
  /// only asserts the response shape; the controller pulls the
  /// decision from its OWN application state (a SEPARATE
  /// pending-verification layer, §A7 / §5.3).
  void decodeResult(Map<String, Object?> json) {
    final state = json['verification_state'];
    if (state is! String) {
      throw const FormatException(
        'community challenge result wire: verification_state must be a string',
      );
    }
    final reason = json['reason_code'];
    if (reason != null && reason is! String) {
      throw const FormatException(
        'community challenge result wire: reason_code must be a string',
      );
    }
  }

  String? cursorQueryValue(Object cursor) {
    if (cursor == const CursorPage.initial()) return null;
    if (cursor is CursorPage) {
      return cursor.cursor;
    }
    throw ArgumentError.value(
      cursor,
      'cursor',
      'cursor must be a CursorPage (initial / continued / haltedAfterRequest)',
    );
  }

  CommunityPage<CommunityChallengeDefinition> decodeChallengeListPage(
    Map<String, Object?> json,
  ) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException(
        'community challenge list wire: items must be a list',
      );
    }
    final items = rawItems
        .whereType<Map>()
        .map((row) {
          final typed = <String, Object?>{};
          row.forEach((key, value) {
            if (key is String) typed[key] = value;
          });
          return decodeChallengeDefinition(typed);
        })
        .toList(growable: false);
    final nextCursor = json['next_cursor'];
    final cursorPage = nextCursor == null
        ? (items.isEmpty
              ? const CursorPage.haltedAfterRequest()
              : const CursorPage.initial())
        : CursorPage.continued(nextCursor as String);
    return CommunityPage<CommunityChallengeDefinition>(
      items: items,
      cursor: cursorPage,
    );
  }

  /// Decode the Kör 23 verified-only leaderboard page wire shape.
  ///
  /// The backend emits ``{"entries": [...], "next_cursor": "..."}``
  /// (D6 / §0.0 wire contract). Each row is decoded into a
  /// :class:`LeaderboardEntry` via the colocated factory
  /// (``rank >= 1`` invariant is enforced there). The return type
  /// is ``CommunityPage<LeaderboardEntry>`` — Dart generic
  /// covariance makes this a valid
  /// ``CommunityPage<Object>`` against the declared interface
  /// signature (D1).
  ///
  /// The cursor mapping mirrors the Kör 22 listChallenges pattern:
  /// a missing ``next_cursor`` with empty ``entries`` halts the
  /// pager; a missing ``next_cursor`` with non-empty ``entries``
  /// resets the cursor to ``initial()`` for the next round; a
  /// non-null ``next_cursor`` produces a ``continued()`` cursor.
  CommunityPage<LeaderboardEntry> decodeLeaderboardPage(
    Map<String, Object?> json,
  ) {
    final rawEntries = json['entries'];
    if (rawEntries is! List) {
      throw const FormatException(
        'community leaderboard wire: entries must be a list',
      );
    }
    final entries = rawEntries
        .whereType<Map>()
        .map((row) {
          final typed = <String, Object?>{};
          row.forEach((key, value) {
            if (key is String) typed[key] = value;
          });
          return decodeLeaderboardEntry(typed);
        })
        .toList(growable: false);
    final nextCursor = json['next_cursor'];
    final cursorPage = nextCursor == null
        ? (entries.isEmpty
              ? const CursorPage.haltedAfterRequest()
              : const CursorPage.initial())
        : CursorPage.continued(nextCursor as String);
    return CommunityPage<LeaderboardEntry>(items: entries, cursor: cursorPage);
  }

  /// Decode a single ``LeaderboardEntry`` row.
  ///
  /// Wire field shape (Kör 23 D6):
  /// * ``public_id`` — string UUID
  /// * ``rank`` — int, 1-based
  /// * ``display_name`` — string|null
  /// * ``handle`` — string|null
  /// * ``metric_value`` — int
  /// * ``submitted_at`` — ISO 8601 string
  /// * ``verified_badge`` — bool (always true for verified-only rows)
  LeaderboardEntry decodeLeaderboardEntry(Map<String, Object?> json) {
    final publicIdValue = json['public_id'];
    if (publicIdValue is! String) {
      throw const FormatException(
        'community leaderboard wire: public_id must be a string',
      );
    }
    final rankValue = json['rank'];
    if (rankValue is! int) {
      throw const FormatException(
        'community leaderboard wire: rank must be an int',
      );
    }
    final metricValue = json['metric_value'];
    if (metricValue is! int) {
      throw const FormatException(
        'community leaderboard wire: metric_value must be an int',
      );
    }
    final submittedAtValue = json['submitted_at'];
    if (submittedAtValue is! String) {
      throw const FormatException(
        'community leaderboard wire: submitted_at must be a string',
      );
    }
    final verifiedBadge = json['verified_badge'];
    if (verifiedBadge is! bool) {
      throw const FormatException(
        'community leaderboard wire: verified_badge must be a bool',
      );
    }
    return LeaderboardEntry(
      publicId: PublicUserId(publicIdValue),
      rank: rankValue,
      displayName: json['display_name'] is String
          ? json['display_name'] as String
          : null,
      handle: json['handle'] is String ? json['handle'] as String : null,
      metricValue: metricValue,
      submittedAt: DateTime.parse(submittedAtValue),
      verifiedBadge: verifiedBadge,
    );
  }

  CommunityChallengeDefinition decodeChallengeDefinition(
    Map<String, Object?> json,
  ) {
    final idValue = json['public_id'];
    if (idValue is! String) {
      throw const FormatException(
        'community challenge wire: public_id must be a string',
      );
    }
    final typeWire = json['type'];
    if (typeWire is! String) {
      throw const FormatException(
        'community challenge wire: type must be a string',
      );
    }
    final type = challengeTypeFromWire(typeWire);
    if (type == null) {
      throw FormatException('community challenge wire: unknown type $typeWire');
    }
    final metric = json['metric'];
    if (metric is! String || metric.isEmpty) {
      throw const FormatException(
        'community challenge wire: metric must be a non-empty string',
      );
    }
    final difficulty = json['difficulty'];
    if (difficulty is! int) {
      throw const FormatException(
        'community challenge wire: difficulty must be an int',
      );
    }
    final startsAt = json['starts_at'];
    final endsAt = json['ends_at'];
    if (startsAt is! String || endsAt is! String) {
      throw const FormatException(
        'community challenge wire: starts_at / ends_at must be strings',
      );
    }
    final authorIdValue = json['author_public_id'];
    if (authorIdValue is! String) {
      throw const FormatException(
        'community challenge wire: author_public_id must be a string',
      );
    }
    final versionValue = json['version'];
    final version = versionValue is int ? versionValue : 1;
    return CommunityChallengeDefinition(
      id: ContentId(idValue),
      version: version,
      type: type,
      metric: metric,
      difficulty: difficulty,
      startsAt: DateTime.parse(startsAt),
      endsAt: DateTime.parse(endsAt),
      authorId: PublicUserId(authorIdValue),
      clubId: json['club_id'] is String ? json['club_id'] as String : null,
    );
  }

  CommunityChallengeParticipantState decodeParticipant({
    required ContentId challengeId,
    required Map<String, Object?> json,
  }) {
    final participantValue = json['participant_public_id'];
    if (participantValue is! String) {
      throw const FormatException(
        'community participant wire: participant_public_id must be a string',
      );
    }
    final stateWire = json['invite_state'];
    if (stateWire is! String) {
      throw const FormatException(
        'community participant wire: invite_state must be a string',
      );
    }
    final state = challengeInviteStateFromWire(stateWire);
    if (state == null) {
      throw FormatException(
        'community participant wire: unknown invite_state $stateWire',
      );
    }
    final bestValue = json['best_metric_value'];
    final bestMetricValue = bestValue is int ? bestValue : null;
    return CommunityChallengeParticipantState(
      challengeId: challengeId,
      participantId: PublicUserId(participantValue),
      inviteState: state,
      bestMetricValue: bestMetricValue,
    );
  }
}

/// The community challenge repository wired against the live
/// ``accountApiClientProvider`` — null on a build where the
/// account layer is disabled, the http impl otherwise.
final communityChallengeRepositoryProvider =
    Provider<CommunityChallengeRepository>((ref) {
      final client = ref.watch(communityChallengeApiClientProvider);
      if (client == null) return const DisabledCommunityChallengeRepository();
      return HttpCommunityChallengeRepository(client);
    });
