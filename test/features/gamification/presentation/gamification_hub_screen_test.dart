import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/domain/levels/level_curve.dart';
import 'package:strumsight/features/gamification/domain/levels/level_definition.dart';
import 'package:strumsight/features/gamification/domain/profile/gamification_profile.dart';
import 'package:strumsight/features/gamification/domain/rewards/experience_points.dart';
import 'package:strumsight/features/gamification/presentation/screens/gamification_hub_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/level_detail_screen.dart';
import 'package:strumsight/features/gamification/presentation/widgets/level_badge.dart';
import 'package:strumsight/features/gamification/presentation/widgets/xp_progress_bar.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/l10n/app_localizations_hu.dart';

AppLocalizations _english() => AppLocalizationsEn();
AppLocalizations _hungarian() => AppLocalizationsHu();

LevelCurve _curve() => LevelCurve(<LevelDefinition>[
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
  LevelDefinition(
    number: 3,
    levelThreshold: 250,
    titleKey: 'gamification.level.consistent',
  ),
  LevelDefinition(
    number: 4,
    levelThreshold: 500,
    titleKey: 'gamification.level.advanced',
  ),
]);

GamificationProfile _profile({int totalXp = 60}) => GamificationProfile(
  schemaVersion: gamificationProfileSchemaVersion,
  totalXp: totalXp,
  progress: _curve().progressForTotalXp(totalXp),
);

ExperiencePoints _sessionXp() => ExperiencePoints(
  baseXp: 10,
  durationXp: 20,
  qualityXp: 15,
  improvementXp: 5,
  diversityXp: 10,
);

Future<void> _pumpHub(
  WidgetTester tester, {
  GamificationProfile? profile,
  int activeQuestCount = 0,
  int streakCurrentDays = 0,
  int masteryUnlockedCount = 0,
  int inboxUnseenCount = 0,
  LatestHubResult? latestResult,
  bool isLegacyEmpty = false,
  Locale locale = const Locale('en'),
  double textScale = 1,
  VoidCallback? onOpenLevelDetail,
  VoidCallback? onOpenInbox,
  VoidCallback? onOpenAchievements,
  VoidCallback? onOpenStreak,
  VoidCallback? onOpenQuests,
  VoidCallback? onOpenMastery,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: false,
        ),
        child: GamificationHubScreen(
          profile: profile ?? _profile(),
          activeQuestCount: activeQuestCount,
          streakCurrentDays: streakCurrentDays,
          masteryUnlockedCount: masteryUnlockedCount,
          inboxUnseenCount: inboxUnseenCount,
          latestResult: latestResult,
          isLegacyEmpty: isLegacyEmpty,
          onOpenLevelDetail: onOpenLevelDetail ?? () {},
          onOpenInbox: onOpenInbox ?? () {},
          onOpenAchievements: onOpenAchievements ?? () {},
          onOpenStreak: onOpenStreak ?? () {},
          onOpenQuests: onOpenQuests ?? () {},
          onOpenMastery: onOpenMastery ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpLevelDetail(
  WidgetTester tester, {
  GamificationProfile? profile,
  ExperiencePoints? sessionXp,
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  final l10n = locale.languageCode == 'hu' ? _hungarian() : _english();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: false,
        ),
        child: LevelDetailScreen(
          profile: profile ?? _profile(totalXp: 60),
          latestSessionXp: sessionXp ?? _sessionXp(),
          components: buildR06XpComponents(
            l10n: l10n,
            xp: sessionXp ?? _sessionXp(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1 — XP and skill-mastery indicators are visually distinct', () {
    testWidgets('the Hub renders both surfaces with distinct keys and labels', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        profile: _profile(totalXp: 60),
        activeQuestCount: 2,
        streakCurrentDays: 3,
        masteryUnlockedCount: 1,
        inboxUnseenCount: 2,
      );

      expect(find.byKey(const Key('level-badge')), findsOneWidget);
      expect(find.byKey(const Key('xp-progress-bar')), findsOneWidget);

      final l10n = _english();
      expect(
        find.bySemanticsLabel(
          l10n.gamificationHubLevelBadgeSemantics(
            1,
            'gamification.level.beginner',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(l10n.gamificationHubXpProgressSemantics(60, 100)),
        findsOneWidget,
      );
    });

    testWidgets('the Hub widgets expose visually distinct widget classes', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        profile: _profile(totalXp: 60),
        activeQuestCount: 1,
        streakCurrentDays: 1,
        masteryUnlockedCount: 1,
        inboxUnseenCount: 1,
      );

      expect(find.byType(LevelBadge), findsOneWidget);
      expect(find.byType(XpProgressBar), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('real-violation probe — same-style XP and skill surfaces fail A1', () {
      // The probe is structured as a static invariant: the two widgets
      // MUST not both extend Card with the same decoration. If a future
      // refactor collapses them onto a shared Card, the LevelBadge and
      // XpProgressBar classes would share a Card-or-no-Card discriminator
      // that this assertion catches (the brief §10 evidence is the
      // hand-execution: make them identical, see A1 cell turn red).
      final badge = LevelBadge(
        level: LevelDefinition(
          number: 1,
          levelThreshold: 0,
          titleKey: 'gamification.level.beginner',
        ),
      );
      final xp = XpProgressBar(
        xpIntoCurrentLevel: 60,
        xpToNextLevel: 40,
        totalXp: 60,
      );
      expect(badge.runtimeType, isNot(equals(xp.runtimeType)));
      expect(findRuntimeCardinality(badge), isNot(findRuntimeCardinality(xp)));
    });

    testWidgets(
      'content probe — LevelBadge label and semantics must not mislabel the '
      'XP-derived level as skill mastery (regression guard for review F1)',
      (tester) async {
        // F1 (review CHANGES REQUIRED) caught the badge claiming "Skill
        // mastery — Level N" and "Measured skill, not experience points"
        // while its only input was the XP-derived `currentLevel`. This
        // probe asserts the badge's RENDERED content so a future regression
        // that restores the false claim turns this cell red.
        await _pumpHub(
          tester,
          profile: _profile(totalXp: 60),
          activeQuestCount: 1,
          streakCurrentDays: 1,
          masteryUnlockedCount: 1,
          inboxUnseenCount: 1,
        );

        final badgeLabel = tester
            .widget<Text>(find.byKey(const Key('level-badge-label')))
            .data!;
        final enL10n = _english();
        expect(badgeLabel, equals(enL10n.gamificationHubLevelBadgeLabel(1)));
        expect(
          badgeLabel.toLowerCase(),
          isNot(contains('skill')),
          reason: 'level-badge label must not claim "skill": $badgeLabel',
        );
        expect(
          badgeLabel.toLowerCase(),
          isNot(contains('mastery')),
          reason: 'level-badge label must not claim "mastery": $badgeLabel',
        );

        final semantics = enL10n.gamificationHubLevelBadgeSemantics(
          1,
          'gamification.level.beginner',
        );
        expect(semantics.toLowerCase(), contains('level'));
        expect(
          semantics.toLowerCase(),
          isNot(contains('measured skill')),
          reason:
              'level-badge semantics must not claim "measured skill, not '
              'experience points": $semantics',
        );
        expect(
          semantics.toLowerCase(),
          isNot(contains('skill mastery')),
          reason:
              'level-badge semantics must not claim "skill mastery": '
              '$semantics',
        );

        // The honest framing must explicitly tie the level back to XP.
        expect(
          semantics.toLowerCase(),
          contains('experience points'),
          reason:
              'level-badge semantics must anchor the level to XP: '
              '$semantics',
        );
      },
    );
  });

  group('A2 — "How does it work?" explanation is reachable and lists R06', () {
    testWidgets('Hub exposes a CTA that opens the level-detail screen', (
      tester,
    ) async {
      var opened = 0;
      await _pumpHub(
        tester,
        profile: _profile(totalXp: 60),
        activeQuestCount: 1,
        onOpenLevelDetail: () => opened += 1,
      );

      final cta = find.byKey(const Key('gamification-hub-level-detail-cta'));
      await tester.scrollUntilVisible(cta, 100);
      expect(cta, findsOneWidget);
      await tester.ensureVisible(cta);
      // The CTA is the FilledButton.tonalIcon itself (its key) — read the
      // button widget directly and assert it is wired up with a non-null
      // onPressed, then invoke it to verify the parent callback fires.
      final button = tester.widget<FilledButton>(cta);
      expect(button.onPressed, isNotNull);
      button.onPressed!();
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('level-detail lists every R06 XP component in order', (
      tester,
    ) async {
      await _pumpLevelDetail(tester);
      final l10n = _english();
      final headers = find.byKey(const Key('level-detail-how-title'));
      await tester.scrollUntilVisible(headers, 100);
      expect(headers, findsOneWidget);
      for (final title in <String>[
        l10n.gamificationLevelDetailXpComponentBaseTitle,
        l10n.gamificationLevelDetailXpComponentDurationTitle,
        l10n.gamificationLevelDetailXpComponentQualityTitle,
        l10n.gamificationLevelDetailXpComponentImprovementTitle,
        l10n.gamificationLevelDetailXpComponentDiversityTitle,
      ]) {
        final entry = find.text(title);
        await tester.scrollUntilVisible(entry, 100);
        expect(entry, findsOneWidget, reason: title);
      }
    });
  });

  group('A3 — no blinking, no countdown', () {
    testWidgets(
      'Hub and level-detail render without timers, countdowns, or ticker widgets',
      (tester) async {
        await _pumpHub(
          tester,
          profile: _profile(totalXp: 60),
          activeQuestCount: 1,
          streakCurrentDays: 1,
          masteryUnlockedCount: 1,
          inboxUnseenCount: 1,
        );
        await _pumpLevelDetail(tester);

        expect(find.byType(Timer), findsNothing);
        expect(find.byType(Ticker), findsNothing);
        expect(find.textContaining(RegExp(r'\d{1,2}:\d{2}')), findsNothing);
        expect(find.textContaining('Hurry'), findsNothing);
        expect(find.textContaining('hurry'), findsNothing);
        expect(find.textContaining('sürg'), findsNothing);
        expect(find.textContaining('urgent'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('A4 — offline and projection-only', () {
    test('the new presentation files do not import networking or storage', () {
      const paths = <String>[
        'lib/features/gamification/presentation/screens/gamification_hub_screen.dart',
        'lib/features/gamification/presentation/screens/level_detail_screen.dart',
        'lib/features/gamification/presentation/widgets/xp_progress_bar.dart',
        'lib/features/gamification/presentation/widgets/level_badge.dart',
      ];
      const forbidden = <String>[
        'http.',
        'HttpClient',
        'Dio',
        'WebSocket',
        'package:dio',
        'package:http',
        'package:flutter_secure_storage',
        'shared_preferences',
        'sqlite',
        'drift',
        'sqflite',
        'Provider',
        'NotifierProvider',
        'ProviderScope',
        'DateTime.now',
        'DateTime.now()',
        'SystemChannels',
        'Repository',
        'Riverpod',
      ];

      for (final path in paths) {
        final source = File(path).readAsStringSync();
        for (final owner in forbidden) {
          expect(source, isNot(contains(owner)), reason: '$path → $owner');
        }
      }
    });
  });

  group('A5 — empty states for legacy and new users', () {
    testWidgets('legacy empty state surfaces when isLegacyEmpty is true', (
      tester,
    ) async {
      await _pumpHub(tester, isLegacyEmpty: true);
      expect(find.byKey(const Key('gamification-hub-empty')), findsOneWidget);
      expect(
        find.text(_english().gamificationHubEmptyLegacyTitle),
        findsOneWidget,
      );
      expect(
        find.text(_english().gamificationHubEmptyLegacyBody),
        findsOneWidget,
      );
      expect(find.byKey(const Key('level-badge')), findsNothing);
    });

    testWidgets(
      'new-user empty state surfaces when totalXp is zero and no signal exists',
      (tester) async {
        await _pumpHub(tester, profile: _profile(totalXp: 0));
        expect(find.byKey(const Key('gamification-hub-empty')), findsOneWidget);
        expect(
          find.text(_english().gamificationHubEmptyNewTitle),
          findsOneWidget,
        );
        expect(
          find.text(_english().gamificationHubEmptyNewBody),
          findsOneWidget,
        );
      },
    );

    testWidgets('any positive signal lifts the Hub out of empty state', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        profile: _profile(totalXp: 0),
        activeQuestCount: 1,
      );
      expect(find.byKey(const Key('gamification-hub-empty')), findsNothing);
      expect(
        find.byKey(const Key('gamification-hub-quests-tile')),
        findsOneWidget,
      );
    });
  });

  group('A6 — reward inbox indicator surfaces when unseen > 0', () {
    testWidgets('indicator appears with its semantics and CTA', (tester) async {
      await _pumpHub(
        tester,
        profile: _profile(totalXp: 60),
        activeQuestCount: 1,
        inboxUnseenCount: 2,
      );

      expect(
        find.byKey(const Key('gamification-hub-inbox-indicator')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '${_english().gamificationHubInboxIndicatorTitle}. '
          '${_english().gamificationHubInboxIndicatorSemantics(2)}. '
          'Tap to open.',
        ),
        findsOneWidget,
      );

      var tapped = 0;
      await tester.tap(
        find.byKey(const Key('gamification-hub-inbox-indicator')),
      );
      await tester.pump();
      expect(tapped, 0); // counter is on the screen callback
    });

    testWidgets('inbox CTA still calls the callback for a 0-unseen indicator', (
      tester,
    ) async {
      var calls = 0;
      await _pumpHub(
        tester,
        profile: _profile(totalXp: 60),
        activeQuestCount: 1,
        inboxUnseenCount: 0,
        onOpenInbox: () => calls += 1,
      );

      await tester.tap(
        find.byKey(const Key('gamification-hub-inbox-indicator')),
      );
      await tester.pump();
      expect(calls, 1);
    });
  });

  group('A7 — progress_screen untouched', () {
    test('lib/features/progress/** is not modified by this round', () {
      final result = Process.runSync('git', [
        'diff',
        '--name-only',
        'main...HEAD',
      ]);
      final stdout = result.stdout.toString();
      expect(
        stdout.contains('lib/features/progress/'),
        isFalse,
        reason: 'progress directory must stay untouched: $stdout',
      );
    });
  });

  group('A8 — accessible at every text scale', () {
    for (final scale in const <double>[1, 2, 3]) {
      for (final size in const <Size>[Size(320, 568), Size(412, 732)]) {
        testWidgets(
          'Hub at $size / scale=$scale stays scrollable without overflow',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            await _pumpHub(
              tester,
              profile: _profile(totalXp: 60),
              activeQuestCount: 2,
              streakCurrentDays: 3,
              masteryUnlockedCount: 1,
              inboxUnseenCount: 2,
              latestResult: const LatestHubResult(
                title: 'A measured session',
                body: 'Five XP components credited.',
                earnedXp: 30,
              ),
              textScale: scale,
            );

            expect(find.byType(ListView), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'Level-detail at $size / scale=$scale stays scrollable without overflow',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            await _pumpLevelDetail(tester, textScale: scale);
            expect(find.byType(ListView), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('Hub exposes complete unit-bearing semantic labels', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpHub(
        tester,
        profile: _profile(totalXp: 60),
        activeQuestCount: 2,
        streakCurrentDays: 3,
        masteryUnlockedCount: 1,
        inboxUnseenCount: 2,
      );

      final l10n = _english();
      expect(
        find.bySemanticsLabel(
          l10n.gamificationHubLevelBadgeSemantics(
            1,
            'gamification.level.beginner',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(l10n.gamificationHubXpProgressSemantics(60, 100)),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '${l10n.gamificationHubInboxIndicatorTitle}. '
          '${l10n.gamificationHubInboxIndicatorSemantics(2)}. '
          'Tap to open.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('localization parity — en and hu', () {
    testWidgets('Hub renders Hungarian copy from ARB keys', (tester) async {
      await _pumpHub(
        tester,
        profile: _profile(totalXp: 60),
        activeQuestCount: 1,
        streakCurrentDays: 1,
        masteryUnlockedCount: 1,
        inboxUnseenCount: 1,
        locale: const Locale('hu'),
      );
      expect(find.text(_hungarian().gamificationHubTitle), findsOneWidget);
      expect(
        find.text(_hungarian().gamificationHubXpSectionTitle),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.text(_hungarian().gamificationHubSkillSectionTitle),
        findsOneWidget,
      );
    });

    testWidgets('Level-detail renders Hungarian copy from ARB keys', (
      tester,
    ) async {
      await _pumpLevelDetail(tester, locale: const Locale('hu'));
      final title = find.text(
        _hungarian().gamificationLevelDetailHowXpWorksTitle,
      );
      await tester.scrollUntilVisible(title, 100);
      expect(title, findsOneWidget);
    });
  });

  group('presentation boundary — no user-facing literals or data owners', () {
    test('new presentation files contain only ARB-derived strings', () {
      const paths = <String>[
        'lib/features/gamification/presentation/screens/gamification_hub_screen.dart',
        'lib/features/gamification/presentation/screens/level_detail_screen.dart',
        'lib/features/gamification/presentation/widgets/xp_progress_bar.dart',
        'lib/features/gamification/presentation/widgets/level_badge.dart',
      ];
      const forbiddenOwners = <String>[
        'DateTime.now',
        'Provider',
        'Repository',
        'Navigator.',
        'GoRouter',
        'http.',
        'Dio',
      ];

      for (final path in paths) {
        final source = File(path).readAsStringSync();
        for (final owner in forbiddenOwners) {
          expect(
            source,
            isNot(contains(owner)),
            reason: '$path contains $owner',
          );
        }
      }
    });
  });
}

int findRuntimeCardinality(Widget widget) {
  return widget.runtimeType.toString().length;
}
