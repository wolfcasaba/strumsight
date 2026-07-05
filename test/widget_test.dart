// Smoke test: the app boots and shows its title on the placeholder screen.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_theory/main.dart';

void main() {
  testWidgets('App boots and shows the title', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MusicTheoryApp()));
    await tester.pumpAndSettle();

    expect(find.text('Music Theory'), findsWidgets);
  });
}
