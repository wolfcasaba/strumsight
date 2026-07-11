import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/tuner/widgets/cents_gauge.dart';
import 'package:music_theory/l10n/app_localizations.dart';

/// Round 88 — the cents gauge is a pure CustomPaint: without a semantics
/// label a screen-reader user gets NOTHING from the tuner's core readout.
/// The label speaks the same fact the triangle shows: how far off, and
/// which way ("18 cents sharp" / "18 cents flat" / "In tune").
Future<void> pumpGauge(WidgetTester tester,
        {required double cents, required bool inTune}) =>
    tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: CentsGauge(cents: cents, inTune: inTune)),
    ));

void main() {
  testWidgets('sharp reading is spoken with direction and rounded cents',
      (tester) async {
    await pumpGauge(tester, cents: 17.6, inTune: false);
    expect(find.bySemanticsLabel('18 cents sharp'), findsOneWidget);
  });

  testWidgets('flat reading is spoken as flat with the magnitude',
      (tester) async {
    await pumpGauge(tester, cents: -18.2, inTune: false);
    expect(find.bySemanticsLabel('18 cents flat'), findsOneWidget);
  });

  testWidgets('in tune is spoken as the achievement, not a number',
      (tester) async {
    await pumpGauge(tester, cents: 2, inTune: true);
    expect(find.bySemanticsLabel('In tune'), findsOneWidget);
  });
}
