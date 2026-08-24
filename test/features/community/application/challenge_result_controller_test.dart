/// Community challenge result submission controller tests
/// (E09-R22, ADR 0417, brief §5.3).
///
/// The §A7 cell — a community-upload failure MUST NOT erase
/// the local-session success. The controller's job is to surface
/// the upload failure in a banner (``state.lastError``) without
/// disturbing the local result the user just earned.
///
/// Architecture notes (matching the relationship controller
/// test pattern — E09-R07):
///
/// * The fake repository implements the Kör 5 (ADR 0399)
///   ``CommunityChallengeRepository`` contract and is wired
///   through ``communityChallengeResultRepositoryProvider``,
///   the SAME provider the controller reads. The production
///   wiring override lives in
///   ``challenge_repository_impl.dart``; the test overrides it
///   explicitly.
/// * The test does NOT exercise the HTTP layer — it asserts
///   the controller's error-handling contract via the fake.
///   The HTTP-shape test is the F3 fixture in
///   ``relationship_controller_test.dart`` for comparison.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/community/application/controllers/challenge_result_controller.dart';
import 'package:strumsight/features/community/domain/entities/community_challenge.dart';
import 'package:strumsight/features/community/domain/repositories/challenge_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';

class _FakeCommunityChallengeRepository
    implements CommunityChallengeRepository {
  _FakeCommunityChallengeRepository();

  AppFailure? submitFailure;
  int submitCalls = 0;

  final List<
    ({
      ContentId challengeId,
      int metricValue,
      String sourceEventId,
      String idempotencyKey,
    })
  >
  recordedSubmissions =
      <
        ({
          ContentId challengeId,
          int metricValue,
          String sourceEventId,
          String idempotencyKey,
        })
      >[];

  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async {
    submitCalls++;
    recordedSubmissions.add((
      challengeId: challengeId,
      metricValue: metricValue,
      sourceEventId: sourceEventId,
      idempotencyKey: idempotencyKey,
    ));
    if (submitFailure != null) throw submitFailure!;
  }

  // ---- the Kör 5 contract (unimplemented for this round) -----------------

  @override
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  }) async => throw UnimplementedError(
    'listChallenges is not exercised in Kör 22 tests',
  );

  @override
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  }) async => throw UnimplementedError(
    'fetchDefinition is not exercised in Kör 22 tests',
  );

  @override
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  }) async => throw UnimplementedError(
    'fetchMyParticipation is not exercised in Kör 22 tests',
  );

  @override
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async =>
      throw UnimplementedError('invite is not exercised in Kör 22 tests');

  @override
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async =>
      throw UnimplementedError('acceptInvite is not exercised in Kör 22 tests');

  @override
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async => throw UnimplementedError(
    'declineInvite is not exercised in Kör 22 tests',
  );

  @override
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async =>
      throw UnimplementedError('cancelInvite is not exercised in Kör 22 tests');

  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async => throw UnimplementedError('leaderboard is Kör 23 scope');
}

ProviderContainer _container(_FakeCommunityChallengeRepository repo) {
  return ProviderContainer(
    overrides: [
      communityChallengeResultRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

void main() {
  group(
    'A7 — community-upload failure does NOT delete local session success',
    () {
      test('a network failure surfaces as localOnly with lastError '
          'captured (the §5.3 invariant)', () async {
        final repo = _FakeCommunityChallengeRepository()
          ..submitFailure = const NetworkFailure(
            code: FailureCode.networkUnavailable,
          );
        final container = _container(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          communityChallengeSubmissionControllerProvider.notifier,
        );
        final challengeId = ContentId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f81');

        await controller.submitResult(
          challengeId: challengeId,
          metricValue: 750,
          sourceEventId: 'evt-a7-1',
          idempotencyKey: 'a7-1',
        );

        final state = container
            .read(communityChallengeSubmissionControllerProvider)
            .value!;
        expect(state.submission, ChallengeResultSubmissionState.localOnly);
        expect(state.isUploading, isFalse);
        expect(state.lastError, isA<AppFailure>());
        expect(
          state.lastError!.code,
          FailureCode.networkUnavailable,
          reason: 'A7 violated — lastError should carry the original code',
        );
        expect(repo.submitCalls, 1, reason: 'repository was called once');
        // The contract: every submit call records the same
        // source_event_id (the server is the idempotency surface —
        // the same id may be safely retried; §D2 / §A1).
        expect(repo.recordedSubmissions.single.sourceEventId, 'evt-a7-1');
      });

      test('a non-network AppFailure (StorageFailure) also lands in '
          'localOnly without deleting local-session success', () async {
        // §A7 is broader than "fail gracefully on NetworkFailure":
        // every repository failure (any AppFailure type) becomes
        // localOnly. The local-session success lives in the caller's
        // domain; the controller MUST never delete or undo it.
        final repo = _FakeCommunityChallengeRepository()
          ..submitFailure = const StorageFailure();
        final container = _container(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          communityChallengeSubmissionControllerProvider.notifier,
        );
        await controller.submitResult(
          challengeId: ContentId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f82'),
          metricValue: 100,
          sourceEventId: 'evt-a7-2',
          idempotencyKey: 'a7-2',
        );

        final state = container
            .read(communityChallengeSubmissionControllerProvider)
            .value!;
        expect(state.submission, ChallengeResultSubmissionState.localOnly);
        expect(state.lastError, isA<StorageFailure>());
      });

      test('a successful upload flips to pending (not synced — the '
          'verified badge is the next participant-state refresh)', () async {
        final repo = _FakeCommunityChallengeRepository();
        final container = _container(repo);
        addTearDown(container.dispose);

        final controller = container.read(
          communityChallengeSubmissionControllerProvider.notifier,
        );
        await controller.submitResult(
          challengeId: ContentId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f83'),
          metricValue: 500,
          sourceEventId: 'evt-a7-3',
          idempotencyKey: 'a7-3',
        );

        final state = container
            .read(communityChallengeSubmissionControllerProvider)
            .value!;
        expect(state.submission, ChallengeResultSubmissionState.pending);
        expect(state.lastError, isNull);
        expect(state.isUploading, isFalse);
      });
    },
  );

  group('controller lifecycle — uploading ↔ pending ↔ localOnly', () {
    test('a second successful submit after pending lands as pending '
        'and increments the recorded submission', () async {
      final repo = _FakeCommunityChallengeRepository();
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        communityChallengeSubmissionControllerProvider.notifier,
      );
      final challengeId = ContentId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f84');
      await controller.submitResult(
        challengeId: challengeId,
        metricValue: 100,
        sourceEventId: 'evt-lc-1',
        idempotencyKey: 'k1',
      );
      await controller.submitResult(
        challengeId: challengeId,
        metricValue: 200,
        sourceEventId: 'evt-lc-2',
        idempotencyKey: 'k2',
      );

      expect(repo.submitCalls, 2);
      final state = container
          .read(communityChallengeSubmissionControllerProvider)
          .value!;
      expect(state.submission, ChallengeResultSubmissionState.pending);
      // Different source_event_ids are recorded — the server-side
      // replay-dedup (§A1) is the canonical idempotency surface.
      expect(repo.recordedSubmissions.length, 2);
      expect(repo.recordedSubmissions[0].sourceEventId, 'evt-lc-1');
      expect(repo.recordedSubmissions[1].sourceEventId, 'evt-lc-2');
    });

    test('clearError() drops the lastError without touching the '
        'submission state', () async {
      final repo = _FakeCommunityChallengeRepository()
        ..submitFailure = const NetworkFailure();
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        communityChallengeSubmissionControllerProvider.notifier,
      );
      await controller.submitResult(
        challengeId: ContentId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f85'),
        metricValue: 100,
        sourceEventId: 'evt-a7-clear',
        idempotencyKey: 'k-clear',
      );

      final before = container
          .read(communityChallengeSubmissionControllerProvider)
          .value!;
      expect(before.lastError, isNotNull);

      controller.clearError();

      final after = container
          .read(communityChallengeSubmissionControllerProvider)
          .value!;
      expect(after.lastError, isNull);
      expect(
        after.submission,
        ChallengeResultSubmissionState.localOnly,
        reason: 'clearError must NOT change the submission state',
      );
    });

    test('markSynced() advances pending → synced', () async {
      final repo = _FakeCommunityChallengeRepository();
      final container = _container(repo);
      addTearDown(container.dispose);

      final controller = container.read(
        communityChallengeSubmissionControllerProvider.notifier,
      );
      await controller.submitResult(
        challengeId: ContentId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f86'),
        metricValue: 500,
        sourceEventId: 'evt-a7-sync',
        idempotencyKey: 'k-sync',
      );

      final before = container
          .read(communityChallengeSubmissionControllerProvider)
          .value!;
      expect(before.submission, ChallengeResultSubmissionState.pending);

      controller.markSynced();

      final after = container
          .read(communityChallengeSubmissionControllerProvider)
          .value!;
      expect(after.submission, ChallengeResultSubmissionState.synced);
    });
  });
}
