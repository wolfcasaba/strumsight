/// Dio-backed implementation of [CommunityChallengeRepository]
/// (E09-R21, ADR 0415).
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
///   ``leaderboard``) raise ``UnimplementedError`` — Kör 22 / 23
///   scope, the Kör 21 ``allowed_paths`` does not include their
///   wire surfaces (the §0.0 D6 / ADR 0415 §D6 scope-shrink).
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

/// The single ``communityChallengeApiClient`` provider. Built
/// lazily so the account-disabled build never constructs the Dio
/// client at all — the same pattern as ``communitySocialApiClient
/// Provider`` in ``relationship_repository_impl.dart``.
final communityChallengeApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

/// Disabled-mode fallback: returns ``ConfigurationFailure`` for
/// every call. Mirrors the pattern of
/// ``DisabledSocialGraphRepository`` /
/// ``DisabledCommunityProfileRepository`` so the controller code
/// path is uniform across the three repository flavors.
final class DisabledCommunityChallengeRepository
    implements CommunityChallengeRepository {
  const DisabledCommunityChallengeRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  }) async =>
      throw _disabled.error;

  @override
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  }) async =>
      throw _disabled.error;

  @override
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  }) async =>
      throw _disabled.error;

  @override
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async =>
      throw _disabled.error;

  @override
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async =>
      throw _disabled.error;

  @override
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async =>
      throw _disabled.error;

  @override
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async =>
      throw _disabled.error;

  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError(
      'submitResult is Kör 22 scope; the Kör 21 surface is invite-only.',
    );
  }

  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async {
    throw UnimplementedError(
      'leaderboard is Kör 23 scope; the Kör 21 surface is invite-only.',
    );
  }
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
    final cursorValue = _cursorQueryValue(cursor);
    if (cursorValue != null) params['cursor'] = cursorValue;
    final result = await _client.getJson<dynamic>(
      '/community/challenges',
      decode: _decodeChallengeListPage,
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
      decode: _decodeChallengeDefinition,
    );
    return switch (result) {
      Success(:final value) =>
        value as CommunityChallengeDefinition,
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
      Success(:final value) {
        if (value is! Map) {
          return null;
        }
        if (value['participant'] == null) {
          return null;
        }
        return _decodeParticipant(
          challengeId: challengeId,
          json: value['participant'] as Map<String, Object?>,
        );
      },
      Failure(:final error) => throw error,
    };
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
      throw (result).error;
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
      throw (result).error;
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
      throw (result).error;
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
      throw (result).error;
    }
  }

  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError(
      'submitResult is Kör 22 scope; the Kör 21 surface is invite-only.',
    );
  }

  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async {
    throw UnimplementedError(
      'leaderboard is Kör 23 scope; the Kör 21 surface is invite-only.',
    );
  }

  // ---- internal ----------------------------------------------------------

  String? _cursorQueryValue(Object cursor) {
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

  CommunityPage<CommunityChallengeDefinition> _decodeChallengeListPage(
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
          return _decodeChallengeDefinition(typed);
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

  CommunityChallengeDefinition _decodeChallengeDefinition(
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
      throw FormatException(
        'community challenge wire: unknown type $typeWire',
      );
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

  CommunityChallengeParticipantState _decodeParticipant({
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

/// The Community challenge repository wired against the live
/// ``accountApiClientProvider`` — null on a build where the
/// account layer is disabled, the http impl otherwise.
final communityChallengeRepositoryProvider =
    Provider<CommunityChallengeRepository>((ref) {
      final client = ref.watch(communityChallengeApiClientProvider);
      if (client == null) return const DisabledCommunityChallengeRepository();
      return HttpCommunityChallengeRepository(client);
    });
