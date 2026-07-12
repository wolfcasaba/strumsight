import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/widgets/wrapped_prompt.dart';
import 'package:music_theory/l10n/app_localizations.dart';

/// Round 153 — the post-win Wrapped prompt (chunk 017 rec #5 auto-prompt
/// half): offered exactly when pride is fresh (≥80%), never as noise below.
void main() {
  Widget app(double accuracy) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: WrappedPrompt(accuracy: accuracy, onOpen: () {}),
        ),
      );

  testWidgets('a good run (≥80%) offers the weekly share', (tester) async {
    await tester.pumpWidget(app(0.85));
    await tester.pumpAndSettle();
    expect(find.text('Share my week'), findsOneWidget);
  });

  testWidgets('below the threshold the prompt stays silent', (tester) async {
    await tester.pumpWidget(app(0.79));
    await tester.pumpAndSettle();
    expect(find.text('Share my week'), findsNothing,
        reason: 'a weak run is not a share moment — no prompt spam');
  });
}
