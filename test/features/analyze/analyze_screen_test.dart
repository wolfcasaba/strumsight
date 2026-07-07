import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/main.dart';

import '../../support/fake_engines.dart';

void main() {
  testWidgets('Analyze tab shows the Record CTA (no more "coming soon")',
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

    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();

    expect(find.text('Record'), findsOneWidget);
    expect(find.textContaining('timeline'), findsOneWidget); // intro copy
    expect(find.textContaining('Coming in'), findsNothing); // placeholder gone
  });
}
