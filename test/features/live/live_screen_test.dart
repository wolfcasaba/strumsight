import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/mock_strum_engine.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/main.dart';

import '../../support/fake_engines.dart';

void main() {
  testWidgets('Live renders the current chord and confidence from a frame',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [strumEngineProvider.overrideWithValue(engine)],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Feed a realistic frame (chord C, an accented downstroke at 90%).
    engine.emit(MockStrumEngine(bpm: 96).frameAt(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('C'), findsOneWidget); // the huge current chord
    expect(find.textContaining('90%'), findsOneWidget); // confidence pill
    expect(find.textContaining('DOWN'), findsOneWidget);
    // The Tuner action button is present on the Live screen.
    expect(find.text('Tuner'), findsWidgets);
  });

  testWidgets('Pause freezes the display and toggles the action label',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [strumEngineProvider.overrideWithValue(engine)],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();
    engine.emit(MockStrumEngine(bpm: 96).frameAt(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
    // Pause must actually stop detection, not just freeze the display.
    expect(engine.stopCalls, greaterThan(0));

    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsOneWidget);
    expect(engine.startCalls, greaterThan(0));
  });
}
