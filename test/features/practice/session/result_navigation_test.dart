// E13-R21 §6 A3 — the three-cell result-navigation threshold table.
//
// | cell           | input                                    | expected |
// |----------------|-------------------------------------------|----------|
// | below threshold| session aborted without saving             | 0 nav    |
// | at threshold   | a single completion                        | 1 nav    |
// | above threshold| completion + a second (dual-source) signal | 1 nav    |
//
// `NavigateToResult` is the reducer's own effect (emitted exactly once, on
// `finishing -> completed`, per `practice_session_reducer.dart`); this file
// exercises the PRESENTATION layer's `PracticeEffectListener`, which is
// what actually calls the navigation sink and is the layer this round
// touches (ADR 0079 §8's single-fire gate).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/platform/platform_providers.dart';
import 'package:strumsight/features/practice/application/practice_session_effect.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../fixtures/practice/session/practice_session_test_fixtures.dart';

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

class _RecordingNavigationSink {
  int calls = 0;
  void call() => calls++;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeSessionHost host,
  required _RecordingNavigationSink nav,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practiceSessionHostProvider.overrideWithValue(host),
        practiceFeedbackOutputProvider.overrideWithValue(const _NoopFeedback()),
        practiceResultNavigationSinkProvider.overrideWithValue(nav.call),
        practiceHapticsEnabledProvider.overrideWithValue(false),
        appLifecycleEventsProvider.overrideWithValue(FakeLifecycleEvents()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PracticeSessionScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A3 — result-navigation threshold table', () {
    testWidgets(
      'below threshold: the session is cancelled without ever emitting '
      'NavigateToResult → 0 navigations',
      (tester) async {
        final host = FakeSessionHost();
        final nav = _RecordingNavigationSink();
        addTearDown(host.close);
        host.emitState(practiceSessionStateFor(PracticeSessionStatus.running));
        await _pumpScreen(tester, host: host, nav: nav);

        // A session that aborts without saving (cancelled) transitions the
        // STATE but the reducer never attaches a `NavigateToResult` effect
        // to a `cancelled` transition — only `finishing -> completed` does.
        host.emitState(
          practiceSessionStateFor(PracticeSessionStatus.cancelled),
        );
        await tester.pump(const Duration(milliseconds: 10));

        expect(nav.calls, 0);
      },
    );

    testWidgets('at threshold: exactly one completion → exactly 1 navigation', (
      tester,
    ) async {
      final host = FakeSessionHost();
      final nav = _RecordingNavigationSink();
      addTearDown(host.close);
      host.emitState(practiceSessionStateFor(PracticeSessionStatus.running));
      await _pumpScreen(tester, host: host, nav: nav);

      host.emitEffect(const NavigateToResult());
      await tester.pump(const Duration(milliseconds: 10));

      expect(nav.calls, 1);
    });

    testWidgets('above threshold: completion PLUS a second, independent signal '
        '(dual source — e.g. a system-driven close racing the user one) → '
        'still exactly 1 navigation', (tester) async {
      final host = FakeSessionHost();
      final nav = _RecordingNavigationSink();
      addTearDown(host.close);
      host.emitState(practiceSessionStateFor(PracticeSessionStatus.running));
      await _pumpScreen(tester, host: host, nav: nav);

      // Two independent `NavigateToResult` effects for the SAME screen
      // instance — the single-fire gate in `PracticeEffectListener` must
      // absorb the second one regardless of how many distinct sources
      // produced it.
      host.emitEffect(const NavigateToResult());
      host.emitEffect(const NavigateToResult());
      await tester.pump(const Duration(milliseconds: 10));

      expect(nav.calls, 1);
    });

    testWidgets(
      'a fresh screen instance for a NEW session re-arms the gate — the '
      'guard is per-mount, not global',
      (tester) async {
        final host1 = FakeSessionHost();
        final nav1 = _RecordingNavigationSink();
        addTearDown(host1.close);
        host1.emitState(practiceSessionStateFor(PracticeSessionStatus.running));
        await _pumpScreen(tester, host: host1, nav: nav1);
        host1.emitEffect(const NavigateToResult());
        await tester.pump(const Duration(milliseconds: 10));
        expect(nav1.calls, 1);

        // Force a real unmount between the two screens — a bare second
        // `pumpWidget` at the same tree position can let Flutter reuse the
        // existing `ProviderScope`/`PracticeEffectListener` Elements
        // in-place (`didUpdateWidget`, not a fresh `initState`), which
        // would silently leave the OLD host's subscription attached
        // instead of proving a genuinely new mount. Two distinct route
        // pushes in production never share an Element this way.
        await tester.pumpWidget(const SizedBox.shrink());

        final host2 = FakeSessionHost();
        final nav2 = _RecordingNavigationSink();
        addTearDown(host2.close);
        host2.emitState(practiceSessionStateFor(PracticeSessionStatus.running));
        await _pumpScreen(tester, host: host2, nav: nav2);
        host2.emitEffect(const NavigateToResult());
        await tester.pump(const Duration(milliseconds: 10));
        expect(nav2.calls, 1);
      },
    );
  });
}
