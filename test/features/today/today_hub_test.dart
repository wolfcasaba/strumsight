// E13-R17 — Today Hub (UI-05). A1/A4/A6/A7/A8 (brief §6, §6.1 matrix).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/features/streak/public.dart';
import 'package:strumsight/features/strum_challenge/public.dart';
import 'package:strumsight/features/today/domain/today_plan_repository.dart';
import 'package:strumsight/features/today/domain/today_plan_snapshot.dart';
import 'package:strumsight/features/today/providers/today_providers.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

/// A fake plan source for tests.
///
/// Production no longer reads [UnavailableTodayPlanRepository]: since E18-R18 it
/// reads the shipped COURSE (`CurriculumTodayPlanRepository`), which always offers a
/// rung. The fake stays because the offline-cached and sync-pending states belong to
/// a synced plan source and the curriculum one never produces them — it has nothing
/// to sync.
class _FakeTodayPlanRepository implements TodayPlanRepository {
  const _FakeTodayPlanRepository(this._snapshot);
  final TodayPlanSnapshot _snapshot;

  @override
  TodayPlanSnapshot load() => _snapshot;
}

/// A learner who already has a streak — i.e. not a new user.
///
/// Needed because the new-user greeting outranks every other hero, and since the
/// plan comes from the shipped course "has a plan" is no longer a signal about the
/// learner. What still is: their own history.
class _FixedStreak extends StreakController {
  _FixedStreak(this.days);
  final int days;
  @override
  StreakData build() =>
      StreakData(current: days, longest: days, totalDays: days);
}

/// A learner who already scored the 60-second strum challenge today.
class _FixedStrumChallengeBest extends StrumChallengeBestController {
  _FixedStrumChallengeBest(this.best);
  final StrumChallengeBest best;
  @override
  StrumChallengeBest? build() => best;
}

Widget _host({
  TodayPlanSnapshot? plan,
  bool visionEnabled = false,
  bool visionSetupEnabled = false,
  DateTime? now,
  int streakDays = 0,
  StrumChallengeBest? strumChallengeBest,
}) => ProviderScope(
  overrides: [
    ...preferenceOverrides(),
    if (streakDays > 0)
      streakProvider.overrideWith(() => _FixedStreak(streakDays)),
    if (strumChallengeBest != null)
      strumChallengeBestProvider.overrideWith(
        () => _FixedStrumChallengeBest(strumChallengeBest),
      ),
    if (plan != null)
      todayPlanRepositoryProvider.overrideWithValue(
        _FakeTodayPlanRepository(plan),
      ),
    appConfigProvider.overrideWithValue(
      AppConfig(
        environment: AppEnvironment.development,
        apiBaseUrl: AppConfig.devApiBaseUrl,
        flags: FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          visionEnabled: visionEnabled,
          visionSetupEnabled: visionSetupEnabled,
        ),
        diagnosticsToken: AppConfig.devDiagnosticsToken,
        buildMode: 'test',
        appVersion: 'test',
      ),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TodayHubScreen(now: now ?? DateTime(2026, 8, 25)),
  ),
);

void main() {
  group('a plan that names a curriculum rung', () {
    testWidgets('a BRAND-NEW learner still gets the welcome, not "continue"', (
      tester,
    ) async {
      // The course gives everyone a plan from their first launch, so the hub must
      // not greet someone who has never played with "continue". The zero-state
      // greeting is a deliberate guarantee; what changed is that it now rests on
      // the learner's own history rather than on the absence of a plan.
      await tester.pumpWidget(
        _host(
          plan: const TodayPlanSnapshot(
            availability: TodayPlanAvailability.ready,
            recommendedMissionId: 'mission.eMinor',
            totalTaskCount: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Next:'), findsNothing);
      expect(
        find.byKey(const ValueKey('today-hub-primary-cta')),
        findsOneWidget,
      );
    });

    testWidgets('renders the rung NAME, never its persistence id', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          streakDays: 3,
          plan: const TodayPlanSnapshot(
            availability: TodayPlanAvailability.ready,
            recommendedMissionId: 'mission.eMinor',
            totalTaskCount: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Next: E minor'), findsOneWidget);
      expect(
        find.textContaining('mission.'),
        findsNothing,
        reason:
            'the projection carries an id precisely so the surface can localise '
            'it; printing the id would defeat the point',
      );
    });

    testWidgets('a rung already practised today reads as done, not as a nag', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          plan: const TodayPlanSnapshot(
            availability: TodayPlanAvailability.ready,
            recommendedMissionId: 'mission.eMinor',
            totalTaskCount: 1,
            completedTaskCount: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The completed-day hero wins over the recommendation, and over the
      // new-user greeting: work counted today IS history.
      expect(find.text('Nice work today'), findsOneWidget);
    });
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A1 — exactly one primary action, in every plan state', () {
    Future<void> expectOnePrimaryCta(
      WidgetTester tester,
      TodayPlanSnapshot? plan,
    ) async {
      await tester.pumpWidget(_host(plan: plan));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('today-hub-primary-cta')),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsOneWidget);
    }

    testWidgets('new user (no plan, no history)', (tester) async {
      await expectOnePrimaryCta(tester, null);
    });

    testWidgets('plan ready, not completed', (tester) async {
      await expectOnePrimaryCta(
        tester,
        const TodayPlanSnapshot(
          availability: TodayPlanAvailability.ready,
          recommendedTaskLabel: 'Warm-up: chromatic run',
          completedTaskCount: 1,
          totalTaskCount: 3,
        ),
      );
    });

    testWidgets('day completed — shows a recap, not a dead end', (
      tester,
    ) async {
      await expectOnePrimaryCta(
        tester,
        const TodayPlanSnapshot(
          availability: TodayPlanAvailability.ready,
          completedTaskCount: 3,
          totalTaskCount: 3,
        ),
      );
      expect(find.text('Nice work today'), findsOneWidget);
    });

    testWidgets('offline cached plan', (tester) async {
      await expectOnePrimaryCta(
        tester,
        const TodayPlanSnapshot(
          availability: TodayPlanAvailability.offlineCached,
          recommendedTaskLabel: 'Chord changes: G to C',
          completedTaskCount: 0,
          totalTaskCount: 2,
        ),
      );
    });
  });

  group('A4 — the hub never touches a microphone/camera/wakelock API', () {
    test(
      'no resource-acquisition call sites in the three hub feature dirs',
      () {
        // §0.0/R6.2 — the measured acquisition call sites this diff must not
        // introduce: the live stream, the recorder, the vision coordinator,
        // and the screen wakelock.
        const forbidden = [
          'liveFrameProvider',
          'startRecording',
          'coordinator.acquire',
          'WakelockPlus',
          'CameraController',
        ];
        final dirs = [
          Directory('lib/features/today'),
          Directory('lib/features/practice_hub'),
          Directory('lib/features/profile_hub'),
        ];
        for (final dir in dirs) {
          for (final entity in dir.listSync(recursive: true)) {
            if (entity is! File || !entity.path.endsWith('.dart')) continue;
            final source = entity.readAsStringSync();
            for (final token in forbidden) {
              expect(
                source.contains(token),
                isFalse,
                reason: '${entity.path} must not reference $token',
              );
            }
          }
        }
      },
    );
  });

  group('A6 — offline cached content stays visible, with an offline badge', () {
    testWidgets('offline-cached plan renders the offline badge and the '
        'cached recommendation — not an empty screen', (tester) async {
      await tester.pumpWidget(
        _host(
          plan: const TodayPlanSnapshot(
            availability: TodayPlanAvailability.offlineCached,
            recommendedTaskLabel: 'Chord changes: G to C',
            completedTaskCount: 0,
            totalTaskCount: 2,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Chord changes: G to C'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('sync-pending plan renders the sync badge', (tester) async {
      await tester.pumpWidget(
        _host(
          plan: const TodayPlanSnapshot(
            availability: TodayPlanAvailability.syncPending,
            recommendedTaskLabel: 'Rhythm: down-down-up',
            completedTaskCount: 0,
            totalTaskCount: 1,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Sync pending'), findsOneWidget);
    });
  });

  group('A7 — the Vision card is honest about the rollout flag', () {
    testWidgets('vision disabled: no card at all — a card whose only content '
        'is "not available" advertises what the learner cannot use', (
      tester,
    ) async {
      // The Today hub grew two cards above this one (2026-09-15); on the
      // default 800×600 surface it now sits below the fold, so give the
      // ListView room instead of scrolling past real content.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(visionEnabled: false));
      await tester.pump();

      expect(
        find.textContaining("isn't available in this build"),
        findsNothing,
      );
      expect(find.text('Vision practice'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Vision practice'), findsNothing);
    });

    testWidgets('vision enabled: actionable, no reason text', (tester) async {
      // The Today hub grew two cards above this one (2026-09-15); on the
      // default 800×600 surface it now sits below the fold, so give the
      // ListView room instead of scrolling past real content.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(visionEnabled: true));
      await tester.pump();

      expect(find.textContaining('Use your camera for guided'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Vision practice'),
        findsOneWidget,
      );
    });
  });

  group('the 60-second strum challenge card (2026-09-15)', () {
    testWidgets('renders the card, an honest "no attempt yet", and a Start '
        'CTA that navigates to the challenge without being a second primary '
        'action', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(find.text('60-second strum challenge'), findsOneWidget);
      expect(find.text('No attempt yet today'), findsOneWidget);
      final cta = find.byKey(const ValueKey('today-hub-strum-challenge-cta'));
      expect(cta, findsOneWidget);
      expect(
        find.descendant(of: cta, matching: find.text('Start')),
        findsOneWidget,
      );
      // A1 — the hero keeps the screen's only filled button; the challenge
      // CTA is outlined. A4 — the card only navigates: the route it opens
      // (`AppRoutes.strumChallenge`) is a Stage route that acquires the
      // microphone itself.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(tester.widget(cta), isA<OutlinedButton>());
    });

    testWidgets("shows today's best when one exists", (tester) async {
      await tester.pumpWidget(
        _host(
          strumChallengeBest: const StrumChallengeBest(
            dateKey: '2026-08-25',
            bestScore: 57,
            bestPatterns: 8,
            attempts: 2,
          ),
        ),
      );
      await tester.pump();

      expect(find.text("Today's best: 57"), findsOneWidget);
      expect(find.text('No attempt yet today'), findsNothing);
    });
  });

  group('the privacy promise card (2026-09-15)', () {
    testWidgets('renders the title and all four promises, with no button and '
        'no second primary action', (tester) async {
      // The Today hub grew two cards above this one (2026-09-15); on the
      // default 800×600 surface it now sits below the fold, so give the
      // ListView room instead of scrolling past real content.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(find.text('Private by design'), findsOneWidget);
      expect(find.text('No account needed'), findsOneWidget);
      expect(find.text('Works fully offline'), findsOneWidget);
      expect(find.text('No ads, no subscription'), findsOneWidget);
      expect(find.text('Your audio never leaves the phone'), findsOneWidget);
      // A1 — the card informs, it does not sell: the hero keeps the screen's
      // only filled button and the card adds no CTA of its own.
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  group('A8 — no invented statistic when there is no real data', () {
    testWidgets('new user: streak and progress both read real zero, '
        'never a placeholder number', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(find.text('0'), findsOneWidget); // the streak metric
      // New-user framing (§0.0/D — isNewUser wins over the generic no-plan
      // copy), never a guessed number or a fabricated recommendation.
      expect(
        find.text('Your first practice session takes just a few minutes.'),
        findsOneWidget,
      );
    });
  });
}
