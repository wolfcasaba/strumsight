import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/features/analyze/providers/analyze_providers.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// Round 102 — leaving the Analyze tab mid-recording must RELEASE the mic.
/// The shell disposes the screen on tab switch, but the controller (a
/// non-autoDispose provider, so results survive tab switches) kept the
/// recorder running invisibly — a privacy bug in a mic app.
class _RecordingStub extends AnalyzeController {
  @override
  AnalyzeState build() => const AnalyzeState(phase: AnalyzePhase.recording);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cancelRecording releases the take and resets to idle', () {
    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        analyzeControllerProvider.overrideWith(_RecordingStub.new),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(analyzeControllerProvider.notifier);
    controller.cancelRecording();
    expect(container.read(analyzeControllerProvider).phase, AnalyzePhase.idle);
  });

  test('cancelRecording leaves a finished result alone', () {
    final container = ProviderContainer(overrides: preferenceOverrides());
    addTearDown(container.dispose);
    container.read(analyzeControllerProvider); // idle
    container.read(analyzeControllerProvider.notifier).cancelRecording();
    expect(container.read(analyzeControllerProvider).phase, AnalyzePhase.idle);
  });

  testWidgets('switching tabs away from a recording Analyze cancels it', (
    tester,
  ) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          strumEngineProvider.overrideWithValue(engine),
          analyzeControllerProvider.overrideWith(_RecordingStub.new),
        ],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StrumSightApp)),
    );

    // Mount the Analyze screen (it believes it is recording). E15-R02
    // (ADR 0467 D9): the app boots on the adaptive shell's /today entry
    // point now, and Analyze lives at AppRoutes.practiceAnalyze — navigate
    // there through the router rather than tapping legacy bottom-nav text
    // that no longer exists at boot. Bounded pumps: the recording phase
    // runs a periodic UI ticker, so pumpAndSettle would never settle.
    container.read(routerProvider).go(AppRoutes.practiceAnalyze);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    // The screen must really be MOUNTED (the phase alone is the stub's
    // build value, true even without navigation).
    expect(find.text('Playing — StrumSight is listening…'), findsOneWidget);
    expect(
      container.read(analyzeControllerProvider).phase,
      AnalyzePhase.recording,
    );

    // …then leave: the disposed screen must cancel the take. The old page
    // unmounts only when the route transition FINISHES — pump past it.
    container.read(routerProvider).go(AppRoutes.practiceLearn);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      container.read(analyzeControllerProvider).phase,
      AnalyzePhase.idle,
      reason: 'the mic must not stay hot behind another tab',
    );
  });
}
