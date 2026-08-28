import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// Round 146 — defence in depth for the r137 expected-chord hint: free-play
/// Live must EXPLICITLY clear any hint on entry instead of trusting the nav
/// invariant that a LearnScreen was always disposed first (chunk 016 residual:
/// a future deep-link or Live-inside-Learn entry would silently bias
/// free-play detection toward a stale lesson chord).
void main() {
  testWidgets('entering Live clears a stale expected-chord hint', (
    tester,
  ) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    // A stale hint left behind by a hypothetical un-disposed lesson.
    engine.setExpectedChord('G');

    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();
    // E15-R02 (ADR 0467 D9): the app now boots on the adaptive shell's
    // /today entry point by default; /live is reachable through
    // legacyRedirects' target, AppRoutes.practiceLive.
    container.read(routerProvider).go(AppRoutes.practiceLive);
    await tester.pumpAndSettle();

    expect(
      engine.expectedChordCalls.last,
      isNull,
      reason: 'free-play must never inherit a lesson bias',
    );
  });
}
