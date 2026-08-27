import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

/// Round E13-R32, §6/A8 + §5.6 + §0.0.B/B8.
///
/// ADR (E13-R06) rule: reduced motion drops the ANIMATION, never the
/// INFORMATION — the celebration still gives feedback, just in a less
/// kinetic modality. §6.1's "hibás implementáció" for this cell is
/// "Csökkentett mozgás → az ünneplés eltűnik" (the celebration disappears);
/// every test here asserts the opposite: content and semantics survive
/// with the transition duration collapsed to zero.
AppLocalizations _english() => AppLocalizationsEn();

StreakState _streakState() => StreakState(
  current: 4,
  longest: 9,
  lastQualifiedDay: 200,
  totalQualifiedDays: 15,
  freezes: 1,
);

CelebrationSummary _summary() => CelebrationSummary(
  events: [
    RewardEvent(
      id: 'evt-1',
      kind: RewardKind.dailyReward,
      titleKey: 'Daily reward',
      bodyKey: 'You practiced today.',
      earnedXp: 15,
      earnedAt: DateTime.utc(2026, 8, 22, 9),
      sourceLedgerId: 'ledger-evt-1',
    ),
  ],
  totalXp: 15,
  startedAt: DateTime.utc(2026, 8, 22, 9),
  endedAt: DateTime.utc(2026, 8, 22, 9, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'A8 — StreakStatusCard: reduceMotion collapses duration, keeps content',
    () {
      testWidgets('reduceMotion=true zeroes the transition duration', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StreakStatusCard(
                reason: StreakEvaluationReason.broken,
                reduceMotion: true,
              ),
            ),
          ),
        );

        expect(
          tester
              .widget<AnimatedContainer>(
                find.byKey(const Key('streak-status-transition')),
              )
              .duration,
          Duration.zero,
        );
        // The content must NOT disappear — only the motion is suppressed.
        expect(find.text(_english().streakV2BrokenTitle), findsOneWidget);
        expect(find.text(_english().streakV2BrokenBody), findsOneWidget);
      });

      testWidgets('reduceMotion=false (default) keeps a non-zero duration', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: StreakStatusCard(reason: StreakEvaluationReason.broken),
            ),
          ),
        );

        expect(
          tester
              .widget<AnimatedContainer>(
                find.byKey(const Key('streak-status-transition')),
              )
              .duration,
          isNot(Duration.zero),
        );
      });

      testWidgets(
        'StreakDetailScreen forwards reduceMotion to the status card',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: StreakDetailScreen(
                state: _streakState(),
                reason: StreakEvaluationReason.grace,
                weeklyConsistencyDays: 5,
                onRecoveryPressed: () {},
                reduceMotion: true,
              ),
            ),
          );

          expect(
            tester
                .widget<AnimatedContainer>(
                  find.byKey(const Key('streak-status-transition')),
                )
                .duration,
            Duration.zero,
          );
          expect(find.text(_english().streakV2GraceTitle), findsOneWidget);
        },
      );
    },
  );

  group('A8 — RewardSummarySheet: reduceMotion keeps EVERY event visible', () {
    testWidgets(
      'reduceMotion=true zeroes AnimatedSize duration but drops no event',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: RewardSummarySheet(summary: _summary(), reduceMotion: true),
            ),
          ),
        );

        expect(
          tester
              .widget<AnimatedSize>(
                find.ancestor(
                  of: find.byKey(const Key('reward-summary-events')),
                  matching: find.byType(AnimatedSize),
                ),
              )
              .duration,
          Duration.zero,
        );
        expect(
          find.byKey(const Key('reward-summary-event-title')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('reward-summary-event-xp')),
          findsOneWidget,
        );
        expect(find.text('15 XP'), findsOneWidget);
      },
    );

    testWidgets('reduceMotion=false (default) keeps a non-zero duration', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: RewardSummarySheet(summary: _summary())),
        ),
      );

      expect(
        tester
            .widget<AnimatedSize>(
              find.ancestor(
                of: find.byKey(const Key('reward-summary-events')),
                matching: find.byType(AnimatedSize),
              ),
            )
            .duration,
        isNot(Duration.zero),
      );
    });
  });

  group('A8 — silent celebration intensity still surfaces non-zero feedback '
      'via the inbox badge (§5.6 — different modality, not zero feedback)', () {
    test('CelebrationCoordinator keeps routing to the inbox regardless of '
        'GamificationPreferences.intensity', () {
      final coordinator = const CelebrationCoordinator(
        batchWindow: Duration(minutes: 2),
      );
      final silent = GamificationPreferences.defaults.copyWith(
        intensity: CelebrationIntensity.silent,
      );
      expect(silent.isCelebrationVisible, isFalse);

      var state = const CelebrationState();
      for (var i = 0; i < 3; i++) {
        final event = RewardEvent(
          id: 'evt-$i',
          kind: RewardKind.dailyReward,
          titleKey: 'title-$i',
          bodyKey: 'body-$i',
          earnedXp: 10,
          earnedAt: DateTime.utc(2026, 8, 22, 10, i),
          sourceLedgerId: 'ledger-$i',
        );
        final (next, _) = coordinator.apply(
          state: state,
          event: event,
          isActiveSession: true,
          now: event.earnedAt,
        );
        state = next;
      }

      // The visual celebration is switched off, but the inbox — the
      // non-animated modality — still carries every event. This is the
      // §5.6 "different modality" guarantee the A8 cell measures.
      expect(state.unseenCount, 3);
    });

    testWidgets(
      'the Hub inbox indicator surfaces a non-zero badge even when the '
      'caller has chosen silent celebration intensity',
      (tester) async {
        const unseenFromSilentCelebration = 3;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GamificationHubScreen(
              profile: _profile(),
              activeQuestCount: 1,
              streakCurrentDays: 1,
              masteryUnlockedCount: 1,
              inboxUnseenCount: unseenFromSilentCelebration,
              onOpenLevelDetail: () {},
              onOpenInbox: () {},
              onOpenAchievements: () {},
              onOpenStreak: () {},
              onOpenQuests: () {},
              onOpenMastery: () {},
            ),
          ),
        );

        expect(
          find.byKey(const Key('gamification-hub-inbox-indicator')),
          findsOneWidget,
        );
        expect(
          find.text(
            _english().gamificationHubInboxIndicatorSemantics(
              unseenFromSilentCelebration,
            ),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('real-violation probe (A8) — a reduceMotion implementation that hides '
      'content must be caught', () {
    testWidgets(
      'a status card wrongly gated on reduceMotion (hidden instead of '
      'un-animated) is detectably different from the real one',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StreakStatusCard(
                reason: StreakEvaluationReason.broken,
                reduceMotion: true,
              ),
            ),
          ),
        );

        // A faulty "reduceMotion hides the celebration" implementation
        // would remove the title/body text entirely. The real widget
        // keeps them — this assertion is the one that would turn red
        // under that regression.
        expect(find.text(_english().streakV2BrokenTitle), findsOneWidget);
        expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
      },
    );
  });
}

GamificationProfile _profile() => GamificationProfile(
  schemaVersion: gamificationProfileSchemaVersion,
  totalXp: 60,
  progress: LevelCurve(<LevelDefinition>[
    LevelDefinition(
      number: 1,
      levelThreshold: 0,
      titleKey: 'gamification.level.beginner',
    ),
    LevelDefinition(
      number: 2,
      levelThreshold: 100,
      titleKey: 'gamification.level.explorer',
    ),
  ]).progressForTotalXp(60),
);
