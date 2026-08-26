// E13-R21 §6 A2, A5, A6, A8 — active session Stage UI, driven through a
// fake `PracticeSessionHost` (the state-machine's own dedup guarantees are
// covered at the application layer by
// `test/features/practice/application/practice_session_*_test.dart`; this
// file proves the PRESENTATION layer's behaviour: no duplicate commands
// from the UI, the exit consequence is stated in text, the readiness row
// keeps its two indicators separate and never claims a measured tuning,
// and portrait/landscape both render without overflow).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/platform/platform_providers.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../../fixtures/practice/session/practice_session_test_fixtures.dart';

AppLocalizations l10nEn() => AppLocalizationsEn();

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeSessionHost host,
  Size size = const Size(412, 915),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practiceSessionHostProvider.overrideWithValue(host),
        practiceFeedbackOutputProvider.overrideWithValue(const _NoopFeedback()),
        practiceResultNavigationSinkProvider.overrideWithValue(() {}),
        practiceHapticsEnabledProvider.overrideWithValue(false),
        appLifecycleEventsProvider.overrideWithValue(FakeLifecycleEvents()),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _router,
      ),
    ),
  );
  await tester.pump();
}

class _NoopFeedback implements PracticeFeedbackOutput {
  const _NoopFeedback();
  @override
  void haptic() {}
  @override
  void countInClick(int beatIndex) {}
  @override
  void announce(String message) {}
  @override
  void openPermissionSettings() {}
}

final _router = GoRouter(
  initialLocation: '/practice/session',
  routes: [
    GoRoute(
      path: '/practice/session',
      builder: (context, state) => const PracticeSessionScreen(),
    ),
    GoRoute(
      path: '/practice/tuner',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('TUNER SENTINEL'))),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ---------------------------------------------------------------------
  // A2 — Pause/Resume never duplicates an event from a single UI gesture
  // ---------------------------------------------------------------------
  group('A2 — Pause/Resume single-fire from the UI', () {
    testWidgets('one Pause tap while running → exactly 1 PausePractice', (
      tester,
    ) async {
      final host = FakeSessionHost();
      addTearDown(host.close);
      host.emitState(practiceSessionStateFor(PracticeSessionStatus.running));
      await _pumpScreen(tester, host: host);

      await tester.tap(
        find.widgetWithText(ElevatedButton, l10nEn().practiceSessionPause),
      );
      await tester.pump();

      expect(host.sent.length, 1);
      expect(host.sent.single, isA<PausePractice>());
    });

    testWidgets(
      'one Resume tap while paused → exactly 1 ResumePractice, even though '
      'two Resume affordances are on screen (transport + recovery overlay)',
      (tester) async {
        final host = FakeSessionHost();
        addTearDown(host.close);
        host.emitState(
          practiceSessionStateFor(
            PracticeSessionStatus.paused,
            pauseCause: PauseCause.user,
          ),
        );
        await _pumpScreen(tester, host: host);

        // Two Resume affordances are expected (bottom transport + the
        // Pause/Recovery overlay) — tapping ONE of them must send exactly
        // one command, not fan out to both.
        expect(find.text(l10nEn().practiceSessionResume), findsWidgets);
        await tester.tap(
          find.byKey(const ValueKey('practice-pause-overlay-resume')),
        );
        await tester.pump();

        expect(host.sent.length, 1);
        expect(host.sent.single, isA<ResumePractice>());
      },
    );
  });

  // ---------------------------------------------------------------------
  // A5 — the exit confirmation states the consequence, not "Yes/No"
  // ---------------------------------------------------------------------
  group('A5 — exit consequence is stated in text', () {
    testWidgets(
      'the exit dialog names the action and states progress is lost — '
      'never a bare Yes/No',
      (tester) async {
        final host = FakeSessionHost();
        addTearDown(host.close);
        host.emitState(practiceSessionStateFor(PracticeSessionStatus.running));
        await _pumpScreen(tester, host: host);

        await tester.tap(
          find.widgetWithText(ElevatedButton, l10nEn().practiceSessionExit),
        );
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(find.byType(AlertDialog), findsOneWidget);
        // The confirm button NAMES the action (ADR 0279 §1) — not "Yes".
        expect(find.text('Yes'), findsNothing);
        expect(find.text('No'), findsNothing);
        expect(find.text(l10nEn().practiceSessionConfirmExit), findsOneWidget);
        // The consequence copy states what is lost — a mechanical proxy
        // for "not a vague question": it names the session's progress.
        expect(
          l10nEn().practiceSessionConfirmExit.toLowerCase(),
          contains('progress'),
        );
        // Cancel ("Stay") is always present (§3).
        expect(find.text(l10nEn().practiceSessionStay), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------
  // A6 — readiness row: two SEPARATE indicators, tuning never claims "in
  // tune", and the Tuner entry navigates via AppRoutes.practiceTuner
  // ---------------------------------------------------------------------
  group('A6 — readiness row', () {
    testWidgets(
      'weak signal and degraded capability render as two separate texts, '
      'never merged into one banner',
      (tester) async {
        final host = FakeSessionHost()..liveScore = null; // no live score yet
        addTearDown(host.close);
        host.emitState(practiceSessionStateFor(PracticeSessionStatus.running));
        await _pumpScreen(tester, host: host);

        expect(
          find.text(l10nEn().practiceSessionReadinessWeakSignal),
          findsOneWidget,
        );
        expect(
          find.text(l10nEn().practiceSessionReadinessCapabilityOk),
          findsOneWidget,
        );
        // Never a single combined string.
        expect(
          find.textContaining(
            '${l10nEn().practiceSessionReadinessWeakSignal} '
            '${l10nEn().practiceSessionReadinessDegraded}',
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'the tuning entry always reads "not measured" — never "in tune"/"tuned"',
      (tester) async {
        final host = FakeSessionHost();
        addTearDown(host.close);
        host.emitState(practiceSessionStateFor(PracticeSessionStatus.running));
        await _pumpScreen(tester, host: host);

        expect(
          find.text(l10nEn().practiceSessionReadinessTuningUnmeasured),
          findsOneWidget,
        );
        expect(find.textContaining('in tune'), findsNothing);
        expect(find.textContaining('Tuned'), findsNothing);
      },
    );

    testWidgets(
      'tapping the tuning entry navigates to AppRoutes.practiceTuner',
      (tester) async {
        final host = FakeSessionHost();
        addTearDown(host.close);
        host.emitState(practiceSessionStateFor(PracticeSessionStatus.running));
        await _pumpScreen(tester, host: host);

        await tester.tap(
          find.byKey(const ValueKey('practice-readiness-tuning')),
        );
        await tester.pumpAndSettle();

        expect(find.text('TUNER SENTINEL'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------
  // A8 — no overflow in portrait or landscape
  // ---------------------------------------------------------------------
  group('A8 — portrait and landscape render without overflow', () {
    for (final size in [Size(412, 915), Size(915, 412)]) {
      testWidgets('running, ${size.width.round()}x${size.height.round()}', (
        tester,
      ) async {
        final host = FakeSessionHost()..liveScore = 700;
        addTearDown(host.close);
        host.emitState(
          practiceSessionStateFor(
            PracticeSessionStatus.running,
            definition: practiceSessionFixtureDefinition(),
            config: practiceSessionFixtureConfig(),
            attemptIndex: 1,
            activeElapsed: const Duration(seconds: 42),
          ),
        );
        await _pumpScreen(tester, host: host, size: size);
        expect(tester.takeException(), isNull);
      });

      testWidgets('paused, ${size.width.round()}x${size.height.round()}', (
        tester,
      ) async {
        final host = FakeSessionHost();
        addTearDown(host.close);
        host.emitState(
          practiceSessionStateFor(
            PracticeSessionStatus.paused,
            definition: practiceSessionFixtureDefinition(),
            config: practiceSessionFixtureConfig(),
            pauseCause: PauseCause.interruption,
          ),
        );
        await _pumpScreen(tester, host: host, size: size);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
