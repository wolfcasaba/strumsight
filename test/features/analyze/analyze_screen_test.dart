import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

void main() {
  testWidgets('Analyze tab shows the Record CTA (no more "coming soon")', (
    tester,
  ) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

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

    // E15-R02 (ADR 0467 D9): the app boots on the adaptive shell's /today
    // entry point now; Analyze lives at AppRoutes.practiceAnalyze.
    container.read(routerProvider).go(AppRoutes.practiceAnalyze);
    await tester.pumpAndSettle();

    expect(find.text('Record'), findsOneWidget);
    expect(find.textContaining('timeline'), findsOneWidget); // intro copy
    expect(find.textContaining('Coming in'), findsNothing); // placeholder gone
  });
}
