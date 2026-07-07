import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/core/theme/app_theme.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/analyze/widgets/timeline_view.dart';
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
      home: Scaffold(body: child),
    ),
  );
}

const _result = AnalyzeResult(
  durationSec: 4,
  bpm: 100,
  chords: [
    TimelineChord(label: 'D', startSec: 0, endSec: 2),
    TimelineChord(label: 'Am', startSec: 2, endSec: 4),
  ],
  strums: [],
);

void main() {
  testWidgets('timeline shows concert-pitch labels with no capo', (tester) async {
    await _pump(tester, const TimelineView(result: _result));
    expect(find.text('D'), findsOneWidget);
    expect(find.text('Am'), findsOneWidget);
  });

  testWidgets('capo transposes the timeline labels (view-time)', (tester) async {
    await _pump(tester, const TimelineView(result: _result, capo: 2));
    // D → C, Am → Gm at capo 2. Stored result is untouched (concert pitch).
    expect(find.text('C'), findsOneWidget);
    expect(find.text('Gm'), findsOneWidget);
    expect(find.text('D'), findsNothing);
  });
}
