import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/core/theme/app_theme.dart';
import 'package:music_theory/features/live/model/chord.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/live/widgets/beat_counter.dart';
import 'package:music_theory/features/live/widgets/chord_display.dart';
import 'package:music_theory/features/live/widgets/confidence_pill.dart';
import 'package:music_theory/features/live/widgets/input_level_meter.dart';
import 'package:music_theory/features/live/widgets/strum_arrow.dart';
import 'package:music_theory/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('ChordDisplay shows the current and next chord', (tester) async {
    await _pump(tester, const ChordDisplay(current: Chord('C'), next: Chord('G')));
    expect(find.text('C'), findsOneWidget);
    expect(find.textContaining('G'), findsWidgets); // "NEXT · G"
  });

  testWidgets('ConfidencePill shows direction word and percentage', (tester) async {
    await _pump(
      tester,
      const ConfidencePill(
        strum: Strum(direction: StrumDirection.down, confidence: 0.94),
      ),
    );
    expect(find.textContaining('94%'), findsOneWidget);
    expect(find.textContaining('DOWN'), findsOneWidget);
  });

  testWidgets('ConfidencePill renders nothing without a strum', (tester) async {
    await _pump(tester, const ConfidencePill(strum: null));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('StrumArrow exposes its semantic label', (tester) async {
    await _pump(
      tester,
      const StrumArrow(
        direction: StrumDirection.up,
        confidence: 0.8,
        semanticLabel: 'Upstroke',
      ),
    );
    expect(find.bySemanticsLabel('Upstroke'), findsOneWidget);
  });

  testWidgets('BeatCounter renders all eight slot labels', (tester) async {
    const labels = ['1', '&', '2', '&', '3', '&', '4', '&'];
    final bar = [
      for (var i = 0; i < 8; i++)
        BeatSlot(
          label: labels[i],
          isDownbeat: i.isEven,
          strum: i.isEven
              ? const Strum(direction: StrumDirection.down, confidence: 0.9)
              : null,
        ),
    ];
    await _pump(tester, BeatCounter(bar: bar, activeIndex: 0));
    for (final l in ['1', '2', '3', '4']) {
      expect(find.text(l), findsOneWidget);
    }
    expect(find.text('&'), findsNWidgets(4));
  });

  testWidgets('InputLevelMeter builds at a mid level', (tester) async {
    await _pump(tester, const InputLevelMeter(level: 0.6));
    expect(find.byType(InputLevelMeter), findsOneWidget);
  });
}
