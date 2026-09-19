/// Wire-format tests for the READ side of
/// ``HttpCommunityChallengeRepository`` against the
/// ``backend/app/community/schemas/challenge.py`` contract
/// (production wiring round 2026-09-15).
///
/// The measured defect this round fixed: ``listChallenges`` built a
/// ``limit`` / ``cursor`` map and never sent it (``ApiClient.getJson``
/// takes no query map), so every "load more" re-fetched page one. The
/// first two cells pin the query string; the rest pin the decoders
/// against the exact ``ChallengeDefinitionOut`` /
/// ``ChallengeParticipationOut`` field sets (including the extra
/// fields the entity has no slot for).
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/challenge_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_challenge.dart';
import 'package:strumsight/features/community/domain/repositories/challenge_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';

class _CannedResponse {
  const _CannedResponse({required this.body, required this.status});
  final String body;
  final int status;
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({required this.onFetch});

  final _CannedResponse Function(RequestOptions options) onFetch;
  final List<RequestOptions> captured = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured.add(options);
    final canned = onFetch(options);
    return ResponseBody.fromString(
      canned.body,
      canned.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

HttpCommunityChallengeRepository _buildRepo(_ScriptedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return HttpCommunityChallengeRepository(ApiClient(dio));
}

_ScriptedAdapter _ok(String body) =>
    _ScriptedAdapter(onFetch: (_) => _CannedResponse(body: body, status: 200));

const String _challengeId = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fd0';
const String _authorId = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fd1';

/// One ``ChallengeDefinitionOut`` row — the full schema field set.
const String _definitionOut =
    '{"public_id":"$_challengeId","author_public_id":"$_authorId",'
    '"type":"friends","metric":"score","difficulty":2,'
    '"starts_at":"2026-09-01T00:00:00Z","ends_at":"2026-09-30T00:00:00Z",'
    '"version":1,"club_id":null,"participant_count":3,'
    '"created_at":"2026-08-30T00:00:00Z",'
    '"updated_at":"2026-08-30T00:00:00Z"}';

void main() {
  group('listChallenges query string', () {
    test('sends limit and no cursor on the first page', () async {
      final adapter = _ok('{"items":[$_definitionOut],"next_cursor":"c2"}');
      final repo = _buildRepo(adapter);

      final page = await repo.listChallenges(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      final options = adapter.captured.single;
      expect(options.method, 'GET');
      expect(options.uri.path, '/community/challenges');
      expect(options.uri.queryParameters['limit'], '25');
      expect(options.uri.queryParameters.containsKey('cursor'), isFalse);
      expect(page.items, hasLength(1));
      expect(page.items.single.id, ContentId(_challengeId));
      expect(page.items.single.type, ChallengeType.friends);
      expect(page.items.single.difficulty, 2);
      expect(page.items.single.clubId, isNull);
      expect(page.cursor, const CursorPage.continued('c2'));
    });

    test('forwards a continued cursor', () async {
      final adapter = _ok('{"items":[],"next_cursor":null}');
      final repo = _buildRepo(adapter);

      final page = await repo.listChallenges(
        cursor: const CursorPage.continued('c2'),
        limit: 10,
      );

      expect(adapter.captured.single.uri.queryParameters['cursor'], 'c2');
      expect(adapter.captured.single.uri.queryParameters['limit'], '10');
      expect(page.cursor, const CursorPage.haltedAfterRequest());
    });
  });

  group('detail + participation', () {
    test('fetchDefinition GETs /community/challenges/{id}', () async {
      final adapter = _ok(_definitionOut);
      final repo = _buildRepo(adapter);

      final definition = await repo.fetchDefinition(
        challengeId: ContentId(_challengeId),
      );

      expect(adapter.captured.single.method, 'GET');
      expect(
        adapter.captured.single.path,
        '/community/challenges/$_challengeId',
      );
      expect(definition.authorId.value, _authorId);
      expect(definition.metric, 'score');
    });

    test('fetchMyParticipation decodes a null participant as null', () async {
      final adapter = _ok('{"participant":null}');
      final repo = _buildRepo(adapter);

      final state = await repo.fetchMyParticipation(
        challengeId: ContentId(_challengeId),
      );

      expect(
        adapter.captured.single.path,
        '/community/challenges/$_challengeId/me',
      );
      expect(state, isNull);
    });

    test('fetchMyParticipation decodes the participant row', () async {
      final adapter = _ok(
        '{"participant":{"participant_public_id":"$_authorId",'
        '"challenge_public_id":"$_challengeId","invite_state":"active",'
        '"best_metric_value":42,"joined_at":"2026-09-02T00:00:00Z",'
        '"invite_public_id":null}}',
      );
      final repo = _buildRepo(adapter);

      final state = await repo.fetchMyParticipation(
        challengeId: ContentId(_challengeId),
      );

      expect(state, isNotNull);
      expect(state!.challengeId, ContentId(_challengeId));
      expect(state.participantId.value, _authorId);
      expect(state.inviteState, ChallengeInviteState.active);
      expect(state.bestMetricValue, 42);
    });

    test('an unknown type is a bad-response failure', () {
      final adapter = _ok(
        _definitionOut.replaceFirst('"type":"friends"', '"type":"duel"'),
      );
      final repo = _buildRepo(adapter);

      expect(
        repo.fetchDefinition(challengeId: ContentId(_challengeId)),
        throwsA(
          isA<NetworkFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.networkBadResponse,
          ),
        ),
      );
    });
  });

  group('factory', () {
    CommunityChallengeRepository resolve(ApiClient? client) {
      final container = ProviderContainer(
        overrides: [
          communityChallengeApiClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      return container.read(communityChallengeRepositoryProvider);
    }

    test('null client → disabled stand-in throwing ConfigurationFailure', () {
      final repo = resolve(null);

      expect(repo, isA<DisabledCommunityChallengeRepository>());
      expect(
        repo.listChallenges(cursor: const CursorPage.initial(), limit: 1),
        throwsA(isA<ConfigurationFailure>()),
      );
    });

    test('a client → the HTTP implementation', () {
      expect(
        resolve(ApiClient(Dio())),
        isA<HttpCommunityChallengeRepository>(),
      );
    });
  });
}
