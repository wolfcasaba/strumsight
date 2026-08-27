/// A2 / A5 — pending vs. verified challenge result (E13-R34, brief §6).
///
/// The `community_challenges_screen.dart` action sheet lazily reads
/// `CommunityChallengeRepository.fetchMyParticipation` (only on an
/// explicit tap — the pinned `community_challenges_test.dart` list-render
/// path never triggers it, so its fake — which does not stub
/// `fetchMyParticipation` — keeps passing unmodified).
///
/// * A2 — a `null` `bestMetricValue` (not yet verified) is visually and
///   textually distinct from a verified result.
/// * A5 — the "still pending" copy is NEUTRAL, never an accusation of
///   cheating, in BOTH `en` and `hu` (§6.1 mérce-mátrix).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/features/community/application/controllers/challenge_controller.dart';
import 'package:strumsight/features/community/domain/entities/community_challenge.dart';
import 'package:strumsight/features/community/domain/repositories/challenge_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/community_challenges_screen.dart';

class _RecordingChallengeRepository implements CommunityChallengeRepository {
  _RecordingChallengeRepository();

  CommunityPage<CommunityChallengeDefinition> listResult =
      const CommunityPage<CommunityChallengeDefinition>(
        items: <CommunityChallengeDefinition>[],
        cursor: CursorPage.haltedAfterRequest(),
      );

  CommunityChallengeParticipantState? participation;
  final List<ContentId> participationCalls = <ContentId>[];

  @override
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  }) async => listResult;

  @override
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  }) async => throw UnimplementedError('fetchDefinition is unused.');

  @override
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  }) async {
    participationCalls.add(challengeId);
    return participation;
  }

  @override
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('submitResult is unused.');

  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async => throw UnimplementedError('leaderboard is unused (A1).');
}

Widget _wrap(Widget child, _RecordingChallengeRepository fake, Locale locale) {
  return ProviderScope(
    overrides: [communityChallengeRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: child,
    ),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _RecordingChallengeRepository fake, {
  required Locale locale,
}) async {
  await tester.pumpWidget(
    _wrap(const CommunityChallengesScreen(), fake, locale),
  );
  for (var i = 0; i < 3; i += 1) {
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

CommunityChallengeDefinition _challenge(String id) {
  return CommunityChallengeDefinition(
    id: ContentId(id),
    version: 1,
    type: ChallengeType.friends,
    metric: 'score',
    difficulty: 1,
    startsAt: DateTime.utc(2026, 1, 1),
    endsAt: DateTime.utc(2026, 1, 8),
    authorId: PublicUserId('author-id'),
    clubId: null,
  );
}

void main() {
  group('A2 — pending result is distinct from verified result', () {
    testWidgets('bestMetricValue == null renders the pending key, not the '
        'verified key', (tester) async {
      final fake = _RecordingChallengeRepository();
      fake.listResult = CommunityPage<CommunityChallengeDefinition>(
        items: <CommunityChallengeDefinition>[_challenge('c1')],
        cursor: const CursorPage.haltedAfterRequest(),
      );
      fake.participation = CommunityChallengeParticipantState(
        challengeId: ContentId('c1'),
        participantId: PublicUserId('me'),
        inviteState: ChallengeInviteState.active,
        bestMetricValue: null,
      );
      await _pumpScreen(tester, fake, locale: const Locale('en'));

      await tester.tap(find.text('score'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('challenge-result-pending')), findsOneWidget);
      expect(find.byKey(const Key('challenge-result-verified')), findsNothing);
    });

    testWidgets(
      'bestMetricValue != null renders the verified key with the verified '
      'value and glyph, not the pending key',
      (tester) async {
        final fake = _RecordingChallengeRepository();
        fake.listResult = CommunityPage<CommunityChallengeDefinition>(
          items: <CommunityChallengeDefinition>[_challenge('c1')],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        fake.participation = CommunityChallengeParticipantState(
          challengeId: ContentId('c1'),
          participantId: PublicUserId('me'),
          inviteState: ChallengeInviteState.completed,
          bestMetricValue: 420,
        );
        await _pumpScreen(tester, fake, locale: const Locale('en'));

        await tester.tap(find.text('score'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('challenge-result-verified')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('challenge-result-pending')), findsNothing);
        expect(find.textContaining('420'), findsWidgets);
        expect(find.byIcon(Icons.verified), findsWidgets);
      },
    );

    testWidgets(
      'no participation yet (null) renders neither the pending nor the '
      'verified key',
      (tester) async {
        final fake = _RecordingChallengeRepository();
        fake.listResult = CommunityPage<CommunityChallengeDefinition>(
          items: <CommunityChallengeDefinition>[_challenge('c1')],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        fake.participation = null;
        await _pumpScreen(tester, fake, locale: const Locale('en'));

        await tester.tap(find.text('score'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('challenge-result-pending')), findsNothing);
        expect(
          find.byKey(const Key('challenge-result-verified')),
          findsNothing,
        );
      },
    );
  });

  group('A5 — the pending copy is NEUTRAL, en + hu', () {
    const accusatoryEnglishWords = <String>['cheat', 'cheating', 'fraud'];
    const accusatoryHungarianWords = <String>['csal']; // "csalás" / "csaló"

    testWidgets('en locale: no accusatory word in the pending copy', (
      tester,
    ) async {
      final fake = _RecordingChallengeRepository();
      fake.listResult = CommunityPage<CommunityChallengeDefinition>(
        items: <CommunityChallengeDefinition>[_challenge('c1')],
        cursor: const CursorPage.haltedAfterRequest(),
      );
      fake.participation = CommunityChallengeParticipantState(
        challengeId: ContentId('c1'),
        participantId: PublicUserId('me'),
        inviteState: ChallengeInviteState.active,
        bestMetricValue: null,
      );
      await _pumpScreen(tester, fake, locale: const Locale('en'));
      await tester.tap(find.text('score'));
      await tester.pumpAndSettle();

      final text = tester
          .widget<Text>(find.byKey(const Key('challenge-result-pending')))
          .data!
          .toLowerCase();
      for (final word in accusatoryEnglishWords) {
        expect(text, isNot(contains(word)), reason: 'en copy: "$text"');
      }
    });

    testWidgets('hu locale: no accusatory word in the pending copy', (
      tester,
    ) async {
      final fake = _RecordingChallengeRepository();
      fake.listResult = CommunityPage<CommunityChallengeDefinition>(
        items: <CommunityChallengeDefinition>[_challenge('c1')],
        cursor: const CursorPage.haltedAfterRequest(),
      );
      fake.participation = CommunityChallengeParticipantState(
        challengeId: ContentId('c1'),
        participantId: PublicUserId('me'),
        inviteState: ChallengeInviteState.active,
        bestMetricValue: null,
      );
      await _pumpScreen(tester, fake, locale: const Locale('hu'));
      await tester.tap(find.text('score'));
      await tester.pumpAndSettle();

      final text = tester
          .widget<Text>(find.byKey(const Key('challenge-result-pending')))
          .data!
          .toLowerCase();
      for (final word in accusatoryHungarianWords) {
        expect(text, isNot(contains(word)), reason: 'hu copy: "$text"');
      }
    });
  });

  group('A1 — the join / view-result path never touches the leaderboard', () {
    testWidgets('opening the action sheet and viewing my result never calls '
        'repository.leaderboard()', (tester) async {
      final fake = _RecordingChallengeRepository();
      fake.listResult = CommunityPage<CommunityChallengeDefinition>(
        items: <CommunityChallengeDefinition>[_challenge('c1')],
        cursor: const CursorPage.haltedAfterRequest(),
      );
      fake.participation = CommunityChallengeParticipantState(
        challengeId: ContentId('c1'),
        participantId: PublicUserId('me'),
        inviteState: ChallengeInviteState.completed,
        bestMetricValue: 100,
      );
      await _pumpScreen(tester, fake, locale: const Locale('en'));

      await tester.tap(find.text('score'));
      await tester.pumpAndSettle();

      // repository.leaderboard() throws if ever called (see the fake
      // above) — reaching this point without a crash and with the
      // participation fetch recorded IS the falsification: the join /
      // view-result surface never enrolls the viewer onto a ranking.
      expect(fake.participationCalls, isNotEmpty);
    });
  });
}
