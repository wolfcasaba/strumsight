import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/core/theme/app_theme.dart';
import 'package:music_theory/features/live/model/chord.dart';
import 'package:music_theory/features/live/model/chord_event.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/live/widgets/chord_timeline.dart';
import 'package:music_theory/features/live/widgets/chord_timeline_card.dart';
import 'package:music_theory/features/live/widgets/strum_arrow.dart';
import 'package:music_theory/l10n/app_localizations.dart';

/// Pump a widget inside the app's Material + localization + Riverpod shell.
/// ProviderScope is required because the hero card embeds [ChordDiagram]
/// (a ConsumerWidget that reads the left-handed provider).
Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
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
    ),
  );
}

ChordEvent _event(String label, StrumDirection? dir, int seq) => ChordEvent(
      chord: Chord(label),
      direction: dir,
      confidence: 0.8,
      seq: seq,
      timeSec: seq.toDouble(),
    );

void main() {
  testWidgets('empty events shows the idle "play a chord" prompt',
      (tester) async {
    await _pump(tester, const ChordTimeline(events: [], capo: 0));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(ChordTimeline)),
    );
    expect(find.text(l10n.liveWaitingForChord), findsOneWidget);
  });

  testWidgets('renders each chord label with its strum arrow, newest as hero',
      (tester) async {
    final events = [
      _event('Am', StrumDirection.down, 0),
      _event('F', StrumDirection.up, 1),
      _event('C', StrumDirection.down, 2),
    ];
    await _pump(tester, ChordTimeline(events: events, capo: 0));
    await tester.pumpAndSettle();

    // All three labels are present.
    expect(find.text('Am'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);

    // One arrow per card (all three carry a direction).
    expect(find.byType(StrumArrow), findsNWidgets(3));

    // The newest chord (C) is the single hero card.
    final heroes = find.byWidgetPredicate(
      (w) => w is ChordTimelineCard && w.isHero,
    );
    expect(heroes, findsOneWidget);
    final hero = tester.widget<ChordTimelineCard>(heroes);
    expect(hero.event.chord.label, 'C');

    // History cards are not heroes.
    final history = find.byWidgetPredicate(
      (w) => w is ChordTimelineCard && !w.isHero,
    );
    expect(history, findsNWidgets(2));
  });

  testWidgets('shows the next-ghost when a next chord is known',
      (tester) async {
    final events = [_event('C', StrumDirection.down, 0)];
    await _pump(
      tester,
      ChordTimeline(events: events, next: const Chord('G'), capo: 0),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('next-ghost')), findsOneWidget);
    expect(find.text('G'), findsOneWidget);
  });
}
