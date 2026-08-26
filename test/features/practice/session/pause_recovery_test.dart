// E13-R21 §6 A4 — the widget stores no business state (ADR 0079 §1, §9).
//
// Every value the screen renders is a pure function of the incoming
// `PracticeSessionState` (and the host's live-score primitive) — never a
// local counter, a cached elapsed time, or a locally-tracked pause cause.
// Proof strategy: emit a state, then emit an ENTIRELY new state object
// (never a mutation of the previous one — `PracticeSessionState` is
// `@immutable`) with different values, and assert the screen shows the NEW
// values, not stale ones — a background/foreground cycle looks exactly
// like this from the screen's point of view (ADR 0079 §9: "the widget
// tracks no isPlaying bool, no own elapsed time").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

Future<FakeLifecycleEvents> _pumpScreen(
  WidgetTester tester, {
  required FakeSessionHost host,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final lifecycle = FakeLifecycleEvents();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practiceSessionHostProvider.overrideWithValue(host),
        practiceFeedbackOutputProvider.overrideWithValue(const _NoopFeedback()),
        practiceResultNavigationSinkProvider.overrideWithValue(() {}),
        practiceHapticsEnabledProvider.overrideWithValue(false),
        appLifecycleEventsProvider.overrideWithValue(lifecycle),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PracticeSessionScreen(),
      ),
    ),
  );
  await tester.pump();
  return lifecycle;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A4 — the screen carries no shadow state', () {
    testWidgets(
      'a brand-new state object with a different elapsed/attempt fully '
      'replaces what was shown — no stale local copy survives',
      (tester) async {
        final host = FakeSessionHost()..liveScore = 100;
        addTearDown(host.close);
        host.emitState(
          practiceSessionStateFor(
            PracticeSessionStatus.running,
            attemptIndex: 0,
            activeElapsed: const Duration(seconds: 5),
          ),
        );
        await _pumpScreen(tester, host: host);
        expect(find.textContaining('00:05'), findsOneWidget);
        expect(
          find.textContaining('${l10nEn().practiceSessionAttempt}: 1'),
          findsOneWidget,
        );

        // A brand-new, unrelated PracticeSessionState instance — simulating
        // the host publishing a fresh snapshot after a background/foreground
        // round-trip. If the screen cached ANY of the old values in its own
        // State, this would still show "00:05" / attempt 1.
        host.liveScore = 900;
        host.emitState(
          practiceSessionStateFor(
            PracticeSessionStatus.running,
            attemptIndex: 3,
            activeElapsed: const Duration(minutes: 2, seconds: 17),
          ),
        );
        // A non-zero pump duration — the broadcast-stream state update is
        // delivered on a microtask/timer boundary a bare `pump()` does not
        // reliably flush in this harness.
        await tester.pump(const Duration(milliseconds: 10));

        expect(find.textContaining('00:05'), findsNothing);
        expect(find.textContaining('02:17'), findsOneWidget);
        expect(
          find.textContaining('${l10nEn().practiceSessionAttempt}: 1'),
          findsNothing,
        );
        expect(
          find.textContaining('${l10nEn().practiceSessionAttempt}: 4'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the Pause/Recovery overlay copy is driven ENTIRELY by pauseCause — '
      'a fresh paused state with a different cause changes the copy',
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
        expect(find.text(l10nEn().practiceSessionPausedByUser), findsOneWidget);
        expect(
          find.text(l10nEn().practiceSessionPausedByInterruption),
          findsNothing,
        );

        // Resume, then immediately re-pause with a DIFFERENT cause — a
        // realistic sequence (user resumes, then the phone rings). A new
        // state object each time; nothing carried over from the widget.
        host.emitState(
          practiceSessionStateFor(
            PracticeSessionStatus.paused,
            pauseCause: PauseCause.interruption,
          ),
        );
        await tester.pump(const Duration(milliseconds: 10));

        expect(
          find.text(l10nEn().practiceSessionPausedByInterruption),
          findsOneWidget,
        );
        expect(find.text(l10nEn().practiceSessionPausedByUser), findsNothing);
      },
    );

    testWidgets(
      'backgrounding while running sends exactly one PausePractice(interruption)',
      (tester) async {
        final host = FakeSessionHost();
        addTearDown(host.close);
        host.emitState(practiceSessionStateFor(PracticeSessionStatus.running));
        final lifecycle = await _pumpScreen(tester, host: host);

        lifecycle.emit(AppLifecycleState.paused);
        await tester.pump();

        expect(host.sent.length, 1);
        final sent = host.sent.single;
        expect(sent, isA<PausePractice>());
        expect((sent as PausePractice).cause, PauseCause.interruption);
      },
    );

    testWidgets(
      'returning to the foreground sends nothing — resume is a user decision '
      '(ADR 0079 §9, "no automatic resume")',
      (tester) async {
        final host = FakeSessionHost();
        addTearDown(host.close);
        host.emitState(
          practiceSessionStateFor(
            PracticeSessionStatus.paused,
            pauseCause: PauseCause.interruption,
          ),
        );
        final lifecycle = await _pumpScreen(tester, host: host);

        lifecycle.emit(AppLifecycleState.resumed);
        await tester.pump();

        expect(host.sent, isEmpty);
      },
    );

    testWidgets('backgrounding while idle/ready/preparing sends nothing (only '
        'countIn/running may pause on interruption)', (tester) async {
      for (final status in [
        PracticeSessionStatus.idle,
        PracticeSessionStatus.ready,
        PracticeSessionStatus.preparing,
      ]) {
        final host = FakeSessionHost();
        addTearDown(host.close);
        host.emitState(practiceSessionStateFor(status));
        final lifecycle = await _pumpScreen(tester, host: host);

        lifecycle.emit(AppLifecycleState.paused);
        await tester.pump();

        expect(host.sent, isEmpty, reason: 'status=$status');
      }
    });
  });
}
