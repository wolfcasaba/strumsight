import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/strumsight_app.dart';

// E01-R03 — the mandated bootstrap-failure screen test: a misconfigured
// build shows the localized failure screen with the concrete problems.

void main() {
  testWidgets('shows the localized title and every problem', (tester) async {
    const problems = [
      'production requires an HTTPS STRUMSIGHT_API_URL.',
      'production diagnostics must not use the development token.',
    ];
    await tester.pumpWidget(const BootstrapFailureApp(problems: problems));
    await tester.pumpAndSettle();

    expect(find.text('Configuration error'), findsOneWidget);
    for (final p in problems) {
      expect(find.textContaining(p), findsOneWidget);
    }
  });
}
