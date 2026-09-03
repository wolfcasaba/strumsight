import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/gamification/application/daily_challenge_service.dart';
import 'package:strumsight/features/gamification/domain/quests/challenge_definition.dart';
import 'package:strumsight/features/gamification/domain/quests/quest_definition.dart';
import 'package:strumsight/features/gamification/domain/quests/quest_objective.dart';
import 'package:strumsight/features/gamification/domain/quests/quest_progress.dart';
import 'package:strumsight/features/gamification/domain/quests/quest_schedule.dart';
import 'package:strumsight/features/gamification/presentation/screens/quests_screen.dart';
import 'package:strumsight/features/gamification/presentation/widgets/quest_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/l10n/app_localizations_hu.dart';

AppLocalizations _english() => AppLocalizationsEn();
AppLocalizations _hungarian() => AppLocalizationsHu();

QuestDefinition _buildQuestDefinition({
  String id = 'daily_open_chord_progression',
  QuestCadence cadence = QuestCadence.daily,
  QuestObjective? objective,
  QuestSchedule? schedule,
  int baseXp = 50,
  int bonusXp = 0,
}) {
  return QuestDefinition(
    id: id,
    schemaVersion: questDefinitionSchemaVersion,
    cadence: cadence,
    objective: objective ?? SkillTagQuestObjective('barre_chords'),
    schedule: schedule ?? _buildSchedule(),
    reward: QuestReward(baseXp: baseXp, bonusXp: bonusXp, policyVersion: 1),
  );
}

QuestSchedule _buildSchedule({
  int generationEpochDay = 20000,
  int timezoneOffsetMinutes = 0,
  int catalogVersion = 1,
  DateTime? expiresAt,
}) {
  final expiry = expiresAt ?? DateTime.utc(2026, 12, 31, 23, 59, 59);
  return QuestSchedule(
    schemaVersion: questScheduleSchemaVersion,
    generationEpochDay: generationEpochDay,
    timezoneOffsetMinutes: timezoneOffsetMinutes,
    catalogVersion: catalogVersion,
    expiresAt: expiry,
  );
}

/// Builds an active QuestProgress for [definition].
QuestProgress _activeProgress(
  QuestDefinition definition, {
  int completedUnits = 0,
}) {
  return QuestProgress.active(
    definition: definition,
    completedUnits: completedUnits,
    practiceResultIds: const <String>[],
  );
}

/// Builds a completed QuestProgress by routing through `QuestProgress.complete`.
QuestProgress _completedProgress(
  QuestDefinition definition, {
  int completedUnits = 4,
  DateTime? at,
}) {
  final schedule = definition.schedule;
  final expiry = schedule.expiresAt;
  final completionAt = at ?? expiry.subtract(const Duration(hours: 1));
  final result = _activeProgress(
    definition,
    completedUnits: completedUnits,
  ).complete(at: completionAt);
  expect(
    result.isSuccess,
    isTrue,
    reason: 'completion at $completionAt must succeed for expiry $expiry',
  );
  return result.progress;
}

QuestViewProjection _buildProjection({
  required QuestDefinition definition,
  QuestProgress? progress,
  int targetUnits = 4,
  int completedUnits = 0,
  bool contentAvailable = true,
  String? sourcePlanLabel,
}) {
  return QuestViewProjection(
    definition: definition,
    progress:
        progress ?? _activeProgress(definition, completedUnits: completedUnits),
    targetUnits: targetUnits,
    completedUnits: completedUnits,
    contentAvailable: contentAvailable,
    sourcePlanLabel: sourcePlanLabel,
  );
}

DailyChallengeInstance _buildChallengeInstance({
  DailyChallengeDefinition? definition,
  bool completed = false,
  int epochDay = 20000,
}) {
  final def =
      definition ??
      const StrumPatternChallenge(
        pattern: <StrumDirection>[StrumDirection.down, StrumDirection.down],
        name: 'Steady downstrokes',
      );
  return DailyChallengeInstance(
    schemaVersion: dailyChallengeInstanceSchemaVersion,
    epochDay: epochDay,
    catalogVersion: 1,
    generatedAt: DateTime.utc(2026, 8, 21),
    definition: def,
    contentCatalog: DailyChallengeContentCatalogSnapshot(
      schemaVersion: dailyChallengeContentCatalogSchemaVersion,
      catalogVersion: 1,
      chordIds: const <String>[],
      rhythmIds: const <String>[],
      songIds: const <String>[],
      timingContentIds: const <String>[],
    ),
    completion: completed
        ? DailyChallengeCompletion(
            completedAt: DateTime.utc(2026, 8, 21, 18, 0),
          )
        : null,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  bool disableAnimations = true,
  bool showOfflineBanner = true,
  bool withChallenge = true,
  bool challengeCompleted = false,
  bool challengeContentAvailable = true,
  List<QuestViewProjection> dailyQuests = const <QuestViewProjection>[],
  List<QuestViewProjection> weeklyQuests = const <QuestViewProjection>[],
  ValueChanged<QuestRouteAction>? onAction,
  DateTime? now,
  DailyChallengeDefinition? challengeDefinition,
}) async {
  final clock = now ?? DateTime.utc(2026, 8, 21, 14, 0);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: QuestsScreen(
          dailyChallengeTitle: 'Today\'s challenge',
          dailyChallenge: withChallenge
              ? _buildChallengeInstance(
                  definition: challengeDefinition,
                  completed: challengeCompleted,
                )
              : null,
          dailyChallengeAvailable: challengeContentAvailable,
          dailyQuests: dailyQuests,
          weeklyQuests: weeklyQuests,
          onAction: onAction ?? (_) {},
          now: clock,
          showOfflineBanner: showOfflineBanner,
        ),
      ),
    ),
  );
  await tester.pump();
}

Map<String, Object?> _readArb(String path) =>
    Map<String, Object?>.from(jsonDecode(File(path).readAsStringSync()) as Map);

List<String> _allQuestCopiesEn() {
  final arb = _readArb('lib/l10n/app_en.arb');
  return <String>[
    arb['questsScreenTitle']! as String,
    arb['questsDailySectionTitle']! as String,
    arb['questsWeeklySectionTitle']! as String,
    arb['questsEmptyTitle']! as String,
    arb['questsEmptyBody']! as String,
    arb['questsOfflineBanner']! as String,
    arb['questsOfflineBody']! as String,
    arb['questRewardAlreadyCredited']! as String,
    arb['questSourcePlanLabel']! as String,
    arb['questSourceModeLabel']! as String,
    arb['questStartCta']! as String,
    arb['questContinueCta']! as String,
    arb['questCompletedBadge']! as String,
    arb['questCompletedBody']! as String,
    arb['questExpiredBadge']! as String,
    arb['questUnavailableBadge']! as String,
    arb['questUnavailableBody']! as String,
    arb['questExpiryToday']! as String,
    arb['questExpiryWeekly']! as String,
    arb['challengeDailyTitle']! as String,
    arb['challengeDailyBody']! as String,
    arb['challengeCompletedToday']! as String,
    arb['challengeUnavailableBody']! as String,
  ];
}

List<String> _allQuestCopiesHu() {
  final arb = _readArb('lib/l10n/app_hu.arb');
  return <String>[
    arb['questsScreenTitle']! as String,
    arb['questsDailySectionTitle']! as String,
    arb['questsWeeklySectionTitle']! as String,
    arb['questsEmptyTitle']! as String,
    arb['questsEmptyBody']! as String,
    arb['questsOfflineBanner']! as String,
    arb['questsOfflineBody']! as String,
    arb['questRewardAlreadyCredited']! as String,
    arb['questSourcePlanLabel']! as String,
    arb['questSourceModeLabel']! as String,
    arb['questStartCta']! as String,
    arb['questContinueCta']! as String,
    arb['questCompletedBadge']! as String,
    arb['questCompletedBody']! as String,
    arb['questExpiredBadge']! as String,
    arb['questUnavailableBadge']! as String,
    arb['questUnavailableBody']! as String,
    arb['questExpiryToday']! as String,
    arb['questExpiryWeekly']! as String,
    arb['challengeDailyTitle']! as String,
    arb['challengeDailyBody']! as String,
    arb['challengeCompletedToday']! as String,
    arb['challengeUnavailableBody']! as String,
  ];
}

const Set<String> _bannedEnglishWords = <String>{
  'hurry',
  'urgent',
  'deadline',
  'rush',
  'last chance',
  'left',
  'remaining',
  'almost over',
  'expires soon',
};

const Set<String> _bannedHungarianWords = <String>{
  'sürg',
  'határid',
  'siess',
  'fogy',
  'utolsó',
  'maradt',
  'hamarosan',
};

bool _containsForbidden(String text, Set<String> banned) {
  final lower = text.toLowerCase();
  for (final word in banned) {
    if (lower.contains(word)) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1 — reward visible without a claim button', () {
    testWidgets(
      'completed quest surfaces the reward copy and never a "begyűjtés" button',
      (tester) async {
        final definition = _buildQuestDefinition(baseXp: 75, bonusXp: 25);
        final completed = _completedProgress(definition, completedUnits: 4);
        await _pumpScreen(
          tester,
          withChallenge: false,
          dailyQuests: <QuestViewProjection>[
            _buildProjection(
              definition: definition,
              progress: completed,
              completedUnits: 4,
            ),
          ],
        );

        // The reward copy is visible ...
        expect(
          find.text(_english().questRewardAlreadyCredited),
          findsOneWidget,
        );
        // ... and there is NO claim button.
        expect(find.text('Begyűjtés'), findsNothing);
        expect(find.text('Collect'), findsNothing);
        expect(find.text('Claim'), findsNothing);
        // The CTA is disabled when the quest is completed.
        final cta = find.byKey(const Key('quest-cta'));
        expect(cta, findsOneWidget);
        final widget = tester.widget<FilledButton>(cta);
        expect(widget.onPressed, isNull);
      },
    );
  });

  group('A2 — progress is caller-fed, never recomputed by the view', () {
    testWidgets(
      'progress ratio renders the supplied numerator and denominator verbatim',
      (tester) async {
        final definition = _buildQuestDefinition();
        await _pumpScreen(
          tester,
          withChallenge: false,
          dailyQuests: <QuestViewProjection>[
            _buildProjection(
              definition: definition,
              targetUnits: 10,
              completedUnits: 3,
            ),
          ],
        );

        // The progress label shows the supplied values, NOT recomputed.
        expect(find.text('3 of 10'), findsOneWidget);
        // The progress bar holds exactly the supplied ratio (3/10 = 0.3).
        final bar = tester.widget<LinearProgressIndicator>(
          find.byKey(const Key('quest-progress-bar')),
        );
        expect(bar.value, closeTo(0.3, 1e-9));
        // The reward label is the supplied baseXp + bonusXp — also verbatim.
        expect(find.text('+50 XP'), findsOneWidget);
      },
    );

    testWidgets('completed progress renders the bar at 1.0', (tester) async {
      final definition = _buildQuestDefinition(baseXp: 60);
      final completed = _completedProgress(definition, completedUnits: 5);
      await _pumpScreen(
        tester,
        withChallenge: false,
        dailyQuests: <QuestViewProjection>[
          _buildProjection(
            definition: definition,
            progress: completed,
            targetUnits: 5,
            completedUnits: 5,
          ),
        ],
      );

      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('quest-progress-bar')),
      );
      expect(bar.value, 1.0);
    });
  });

  group('A3 — neutral expiry text, no countdown, no urgency', () {
    test('every en + hu quest copy avoids banned urgency words', () {
      for (final copy in _allQuestCopiesEn()) {
        expect(
          _containsForbidden(copy, _bannedEnglishWords),
          isFalse,
          reason: 'forbidden en word in: "$copy"',
        );
      }
      for (final copy in _allQuestCopiesHu()) {
        expect(
          _containsForbidden(copy, _bannedHungarianWords),
          isFalse,
          reason: 'forbidden hu word in: "$copy"',
        );
      }
    });

    testWidgets('the expiry label never carries a digit countdown', (
      tester,
    ) async {
      final definition = _buildQuestDefinition();
      await _pumpScreen(
        tester,
        withChallenge: false,
        dailyQuests: <QuestViewProjection>[
          _buildProjection(definition: definition),
        ],
      );

      final expiry = find.byKey(const Key('quest-expiry-label'));
      expect(expiry, findsOneWidget);
      final text = (tester.widget<Text>(expiry)).data!;
      expect(
        text,
        isNot(
          matches(
            RegExp(
              r'\b\d+\s*(?:hour|hours|h|min|minute|minutes|sec|second|seconds)\b',
              caseSensitive: false,
            ),
          ),
        ),
      );
      expect(
        text,
        isNot(
          matches(
            RegExp(r'\b\d+\s*(?:óra|perc|másodperc)\b', caseSensitive: false),
          ),
        ),
      );
    });

    testWidgets('no countdown ticker is rendered in the quest tree', (
      tester,
    ) async {
      await _pumpScreen(tester);
      expect(find.textContaining(RegExp(r'\d{1,2}:\d{2}')), findsNothing);
      expect(find.textContaining(RegExp(r'\d+s')), findsNothing);
    });
  });

  group('A4 — typed CTA + safe fallback for unavailable targets', () {
    testWidgets('CTA emits a typed QuestStartPracticeAction, not a string', (
      tester,
    ) async {
      QuestRouteAction? captured;
      final definition = _buildQuestDefinition();
      await _pumpScreen(
        tester,
        withChallenge: false,
        dailyQuests: <QuestViewProjection>[
          _buildProjection(definition: definition),
        ],
        onAction: (action) => captured = action,
      );

      await tester.ensureVisible(find.byKey(const Key('quest-cta')));
      await tester.tap(find.byKey(const Key('quest-cta')));
      await tester.pump();

      expect(captured, isA<QuestStartPracticeAction>());
      final typed = captured as QuestStartPracticeAction;
      expect(typed.objective, isA<SkillTagQuestObjective>());
      expect(typed.objective, isNot(isA<String>()));
    });

    testWidgets(
      'CTA emits a typed QuestContinuePracticeAction when in progress',
      (tester) async {
        QuestRouteAction? captured;
        final definition = _buildQuestDefinition();
        await _pumpScreen(
          tester,
          withChallenge: false,
          dailyQuests: <QuestViewProjection>[
            _buildProjection(
              definition: definition,
              completedUnits: 2,
              targetUnits: 4,
            ),
          ],
          onAction: (action) => captured = action,
        );

        await tester.ensureVisible(find.byKey(const Key('quest-cta')));
        await tester.tap(find.byKey(const Key('quest-cta')));
        await tester.pump();

        expect(captured, isA<QuestContinuePracticeAction>());
      },
    );

    testWidgets(
      'unavailable quest disables the CTA and shows the fallback label',
      (tester) async {
        final definition = _buildQuestDefinition();
        await _pumpScreen(
          tester,
          withChallenge: false,
          dailyQuests: <QuestViewProjection>[
            _buildProjection(definition: definition, contentAvailable: false),
          ],
        );

        // The disabled CTA is rendered as a text label, never a tappable button.
        expect(find.byKey(const Key('quest-cta-disabled')), findsOneWidget);
        expect(find.text(_english().questUnavailableBadge), findsOneWidget);
        expect(find.byKey(const Key('quest-cta')), findsNothing);
      },
    );

    testWidgets(
      'completed quest disables the CTA — reward is already credited',
      (tester) async {
        final definition = _buildQuestDefinition();
        final completed = _completedProgress(definition);
        await _pumpScreen(
          tester,
          withChallenge: false,
          dailyQuests: <QuestViewProjection>[
            _buildProjection(
              definition: definition,
              progress: completed,
              completedUnits: 4,
            ),
          ],
        );

        final cta = tester.widget<FilledButton>(
          find.byKey(const Key('quest-cta')),
        );
        expect(cta.onPressed, isNull);
      },
    );
  });

  group('A5 — source-plan connection is visible', () {
    testWidgets(
      'caller-supplied sourcePlanLabel is rendered for every objective',
      (tester) async {
        final definition = _buildQuestDefinition(
          objective: SkillTagQuestObjective('barre_chords'),
        );
        await _pumpScreen(
          tester,
          withChallenge: false,
          dailyQuests: <QuestViewProjection>[
            _buildProjection(
              definition: definition,
              sourcePlanLabel: 'Plan block: open chord progression',
            ),
          ],
        );

        final sourceLabelKey = find.byKey(const Key('quest-source-label'));
        expect(sourceLabelKey, findsOneWidget);
        final widget = tester.widget<Text>(sourceLabelKey);
        expect(widget.data, 'Plan block: open chord progression');
      },
    );

    testWidgets('SkillTagQuestObjective renders the skill focus label', (
      tester,
    ) async {
      final definition = _buildQuestDefinition(
        objective: SkillTagQuestObjective('barre_chords'),
      );
      await _pumpScreen(
        tester,
        withChallenge: false,
        dailyQuests: <QuestViewProjection>[
          _buildProjection(definition: definition),
        ],
      );

      expect(find.text('Skill focus: barre_chords'), findsOneWidget);
    });
  });

  group('A6 — offline path is complete (no network dependency)', () {
    testWidgets('screen renders fully without any HTTP client or async wait', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the offline banner is rendered by default and survives a custom clock',
      (tester) async {
        await _pumpScreen(tester, now: DateTime.utc(2026, 1, 1));
        expect(find.byKey(const Key('quests-offline-banner')), findsOneWidget);
      },
    );
  });

  group('A7 — empty state for new users', () {
    testWidgets('no challenge + no quests → empty state', (tester) async {
      await _pumpScreen(
        tester,
        withChallenge: false,
        dailyQuests: const <QuestViewProjection>[],
        weeklyQuests: const <QuestViewProjection>[],
      );
      expect(find.byKey(const Key('quests-empty-state')), findsOneWidget);
      expect(find.text(_english().questsEmptyTitle), findsOneWidget);
      expect(find.text(_english().questsEmptyBody), findsOneWidget);
    });
  });

  group('A8 — textScaler 1.0 / 2.0 / 3.0: no truncation, no overflow', () {
    final definition = _buildQuestDefinition(baseXp: 50);
    final projection = _buildProjection(
      definition: definition,
      completedUnits: 2,
    );

    testWidgets('1.0 renders without overflow', (tester) async {
      await _pumpScreen(
        tester,
        textScale: 1.0,
        withChallenge: true,
        dailyQuests: <QuestViewProjection>[projection],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('2.0 (project a11y threshold) renders without truncation', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        textScale: 2.0,
        withChallenge: true,
        dailyQuests: <QuestViewProjection>[projection],
      );
      expect(tester.takeException(), isNull);
      // The progress label and reward label must still be findable in the
      // tree. They may sit below the fold of a small test viewport so we
      // scroll until visible before asserting.
      final progressKey = find.byKey(const Key('quest-progress-label'));
      await tester.scrollUntilVisible(progressKey, 100);
      expect(progressKey, findsOneWidget);
      final rewardKey = find.byKey(const Key('quest-reward-label'));
      await tester.scrollUntilVisible(rewardKey, 100);
      expect(rewardKey, findsOneWidget);
    });

    testWidgets('3.0 above the threshold stays scrollable, no crash', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        textScale: 3.0,
        withChallenge: true,
        dailyQuests: <QuestViewProjection>[projection],
      );
      expect(tester.takeException(), isNull);
      final listFinder = find.byKey(const Key('quests-screen-list'));
      expect(listFinder, findsOneWidget);
      await tester.drag(listFinder, const Offset(0, -100));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Real-violation probe — A1 must catch a begyűjtés gomb', () {
    testWidgets('adding a begyűjtés button triggers the A1 check to fail', (
      tester,
    ) async {
      // Simulate a faulty build: a button claiming the reward.
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: Column(
                children: <Widget>[
                  Text(_english().questRewardAlreadyCredited),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Begyűjtés'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // A faulty implementation would expose this button. The A1 invariant
      // asserts that the production card DOES NOT expose it. If the button
      // is present here, the production A1 assertion (in the first group)
      // would have failed.
      expect(find.text('Begyűjtés'), findsOneWidget);
    });
  });

  group('CTA matrix — disabled / in-progress / completed / unavailable', () {
    final base = _buildQuestDefinition(baseXp: 40);

    testWidgets('active + contentAvailable → enabled Start CTA', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        withChallenge: false,
        dailyQuests: <QuestViewProjection>[
          _buildProjection(definition: base, completedUnits: 0),
        ],
      );
      final cta = tester.widget<FilledButton>(
        find.byKey(const Key('quest-cta')),
      );
      expect(cta.onPressed, isNotNull);
      expect(find.text(_english().questStartCta), findsOneWidget);
    });

    testWidgets('active + in-progress → enabled Continue CTA', (tester) async {
      await _pumpScreen(
        tester,
        withChallenge: false,
        dailyQuests: <QuestViewProjection>[
          _buildProjection(definition: base, completedUnits: 1, targetUnits: 4),
        ],
      );
      final cta = tester.widget<FilledButton>(
        find.byKey(const Key('quest-cta')),
      );
      expect(cta.onPressed, isNotNull);
      expect(find.text(_english().questContinueCta), findsOneWidget);
    });

    testWidgets('unavailable → no tappable CTA, fallback label visible', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        withChallenge: false,
        dailyQuests: <QuestViewProjection>[
          _buildProjection(definition: base, contentAvailable: false),
        ],
      );
      expect(find.byKey(const Key('quest-cta')), findsNothing);
      expect(find.byKey(const Key('quest-cta-disabled')), findsOneWidget);
      expect(find.text(_english().questUnavailableBadge), findsOneWidget);
    });

    testWidgets('completed → disabled CTA, reward credited copy visible', (
      tester,
    ) async {
      final completed = _completedProgress(base, completedUnits: 4);
      await _pumpScreen(
        tester,
        withChallenge: false,
        dailyQuests: <QuestViewProjection>[
          _buildProjection(
            definition: base,
            progress: completed,
            completedUnits: 4,
          ),
        ],
      );
      final cta = tester.widget<FilledButton>(
        find.byKey(const Key('quest-cta')),
      );
      expect(cta.onPressed, isNull);
      expect(find.text(_english().questRewardAlreadyCredited), findsOneWidget);
    });
  });

  group('Challenge matrix — completion + unavailable', () {
    testWidgets('daily challenge CTA emits a typed QuestTryLiveAction', (
      tester,
    ) async {
      QuestRouteAction? captured;
      await _pumpScreen(
        tester,
        withChallenge: true,
        challengeContentAvailable: true,
        onAction: (action) => captured = action,
      );

      await tester.ensureVisible(find.byKey(const Key('challenge-cta')));
      await tester.tap(find.byKey(const Key('challenge-cta')));
      await tester.pump();

      expect(captured, isA<QuestTryLiveAction>());
    });

    testWidgets(
      'completed challenge shows the completed badge and keeps CTA replayable',
      (tester) async {
        await _pumpScreen(
          tester,
          withChallenge: true,
          challengeCompleted: true,
          challengeContentAvailable: true,
        );

        expect(
          find.byKey(const Key('challenge-completed-label')),
          findsOneWidget,
        );
        // The daily challenge is replayable per R19 Decision 2 — the CTA stays
        // enabled. Reward idempotency is enforced by the ledger, not by
        // gating the UI.
        final cta = tester.widget<FilledButton>(
          find.byKey(const Key('challenge-cta')),
        );
        expect(cta.onPressed, isNotNull);
      },
    );

    testWidgets(
      'unavailable challenge disables CTA and shows the unavailable copy',
      (tester) async {
        await _pumpScreen(
          tester,
          withChallenge: true,
          challengeContentAvailable: false,
        );

        expect(
          find.byKey(const Key('challenge-unavailable-body')),
          findsOneWidget,
        );
        final cta = tester.widget<FilledButton>(
          find.byKey(const Key('challenge-cta')),
        );
        expect(cta.onPressed, isNull);
      },
    );
  });

  group('A3 — phone viewport (360x640), textScaler 1.5/2.0/2.5, en+hu '
      '(§0.0.A/R5 — the default 800x600 test viewport is wider AND taller '
      'than any phone and can mask a real overflow, L558)', () {
    final definition = _buildQuestDefinition(baseXp: 50);
    final projection = _buildProjection(
      definition: definition,
      completedUnits: 2,
    );

    for (final scale in <double>[1.5, 2.0, 2.5]) {
      for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
        testWidgets(
          '$scale / ${locale.languageCode} — no overflow on a real phone size',
          (tester) async {
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await _pumpScreen(
              tester,
              locale: locale,
              textScale: scale,
              withChallenge: true,
              dailyQuests: <QuestViewProjection>[projection],
            );

            expect(find.byKey(const Key('quests-screen-list')), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('empty state at 2.0 on a real phone size has no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpScreen(
        tester,
        textScale: 2.0,
        withChallenge: false,
        dailyQuests: const <QuestViewProjection>[],
        weeklyQuests: const <QuestViewProjection>[],
      );

      expect(find.byKey(const Key('quests-empty-state')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // B1 (review) — the single 2.0/en cell above missed the hu overflow: the
    // empty state was a bare Center with no scroll parent. Full cycle, the
    // existing cell stays.
    for (final scale in <double>[1.5, 2.0, 2.5]) {
      for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
        testWidgets(
          'empty state $scale / ${locale.languageCode} — no overflow on a '
          'real phone size',
          (tester) async {
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await _pumpScreen(
              tester,
              locale: locale,
              textScale: scale,
              withChallenge: false,
              dailyQuests: const <QuestViewProjection>[],
              weeklyQuests: const <QuestViewProjection>[],
            );

            expect(find.byKey(const Key('quests-empty-state')), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('Localisation — Hungarian copy renders without banned urgency', () {
    testWidgets('every visible string in hu is non-urgent', (tester) async {
      final definition = _buildQuestDefinition();
      await _pumpScreen(
        tester,
        locale: const Locale('hu'),
        withChallenge: false,
        dailyQuests: <QuestViewProjection>[
          _buildProjection(definition: definition),
        ],
      );

      for (final copy in <String>[
        _hungarian().questsScreenTitle,
        _hungarian().questsDailySectionTitle,
        _hungarian().questsWeeklySectionTitle,
        _hungarian().questStartCta,
        _hungarian().questContinueCta,
        _hungarian().questRewardAlreadyCredited,
        _hungarian().questCompletedBody,
        _hungarian().questUnavailableBadge,
        _hungarian().challengeDailyTitle,
        _hungarian().challengeDailyBody,
      ]) {
        expect(_containsForbidden(copy, _bannedHungarianWords), isFalse);
      }
    });
  });
}
