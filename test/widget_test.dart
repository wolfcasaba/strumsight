// Smoke test: the app boots into the adaptive shell's Today destination
// with bottom navigation (E15-R02, ADR 0467 D1 — the shell is now the
// non-production default).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/main.dart';

import 'support/fake_engines.dart';
import 'support/preference_store.dart';

void main() {
  testWidgets('App boots to the Today tab with bottom navigation', (
    tester,
  ) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          strumEngineProvider.overrideWithValue(engine),
        ],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Bottom-nav destinations (default locale = en). Coach is absent —
    // aiTutorEnabled defaults to false, so only 4 of the 5 areas show.
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Practice hub'), findsWidgets);
    expect(find.text('Song library'), findsWidgets);
    expect(find.text('Tutor profile'), findsWidgets);
  });
}
