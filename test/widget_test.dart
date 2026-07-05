// Smoke test: the app boots into the Live tab with bottom navigation.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/main.dart';

import 'support/fake_engines.dart';

void main() {
  testWidgets('App boots to the Live tab with bottom navigation', (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [strumEngineProvider.overrideWithValue(engine)],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Bottom-nav destinations (default locale = en).
    expect(find.text('Live'), findsWidgets);
    expect(find.text('Analyze'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
