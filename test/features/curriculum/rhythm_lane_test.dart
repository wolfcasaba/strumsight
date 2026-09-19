// The notation row: what it shows, and what it refuses to claim.
//
// Design §2 (honesty) and §3 (the rhythm pillar). The cells here are mostly
// about the ABSENCE of false signals: green only on confirmed evidence, a word
// next to every colour, and an explicit line where there is no chord at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_grid.dart';
import 'package:strumsight/features/curriculum/presentation/widgets/rhythm_lane.dart';
import 'package:strumsight/l10n/app_localizations.dart';

RhythmGrid _dDuUdU() => RhythmGrid.pendulum(
  subdivision: RhythmSubdivision.eighth,
  struck: const [true, false, true, true, false, true, true, true],
);

RhythmGrid _mutedQuarters() => RhythmGrid.pendulum(
  subdivision: RhythmSubdivision.quarter,
  struck: const [true, true, true, true],
  muted: true,
);

Widget _host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: SsDarkTheme.data(),
  home: Scaffold(body: child),
);

/// The colour of the chord bar's border, which is where the fretting state shows.
Color _chordBorderColor(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.ancestor(of: find.text('Em'), matching: find.byType(Container)).first,
  );
  final decoration = container.decoration! as BoxDecoration;
  return (decoration.border! as Border).top.color;
}

void main() {
  group('the chord bar', () {
    testWidgets('green ONLY when the asked chord is confirmed', (tester) async {
      final colors = SsDarkTheme.data().extension<SsColorScheme>()!;
      await tester.pumpWidget(
        _host(
          RhythmLane(
            grid: _dDuUdU(),
            chord: 'Em',
            fretting: FrettingState.ringing,
          ),
        ),
      );
      expect(_chordBorderColor(tester), colors.success);
      expect(find.text('ringing clearly'), findsOneWidget);
    });

    testWidgets('unconfirmed is neutral — never a failure colour', (
      tester,
    ) async {
      final colors = SsDarkTheme.data().extension<SsColorScheme>()!;
      await tester.pumpWidget(
        _host(
          RhythmLane(
            grid: _dDuUdU(),
            chord: 'Em',
            fretting: FrettingState.unconfirmed,
          ),
        ),
      );
      expect(_chordBorderColor(tester), colors.border);
      expect(_chordBorderColor(tester), isNot(colors.danger));
      expect(find.text('not confirmed'), findsOneWidget);
    });

    testWidgets('a different chord is AMBER, not red', (tester) async {
      // A wrong chord is information, not an error: red is reserved for actual
      // errors, and red/green is the pair that merges for the most common
      // colour-vision deficiency.
      final colors = SsDarkTheme.data().extension<SsColorScheme>()!;
      await tester.pumpWidget(
        _host(
          RhythmLane(
            grid: _dDuUdU(),
            chord: 'Em',
            fretting: FrettingState.otherChord,
            heardChord: 'Am',
          ),
        ),
      );
      expect(_chordBorderColor(tester), colors.warning);
      expect(_chordBorderColor(tester), isNot(colors.danger));
      expect(find.text('Am is sounding'), findsOneWidget);
    });

    testWidgets('every state carries a WORD, not colour alone', (tester) async {
      for (final state in FrettingState.values) {
        await tester.pumpWidget(
          _host(
            RhythmLane(
              grid: _dDuUdU(),
              chord: 'Em',
              fretting: state,
              heardChord: 'Am',
            ),
          ),
        );
        // Each state must render some label text beside the chord name.
        expect(
          find.byType(Text),
          findsAtLeast(3),
          reason: '$state must say something in words',
        );
      }
    });

    testWidgets('no chord is SAID, not left as an empty gap', (tester) async {
      // A muted string has no chord to name. A blank space would read as an
      // oversight; the line states the reason.
      await tester.pumpWidget(
        _host(
          RhythmLane(
            grid: _mutedQuarters(),
            chord: null,
            fretting: FrettingState.unconfirmed,
          ),
        ),
      );
      expect(
        find.text('No chord — damp the strings, right hand only'),
        findsOneWidget,
      );
    });
  });

  group('the stroke row', () {
    testWidgets('one glyph per slot, ghosts included', (tester) async {
      await tester.pumpWidget(
        _host(
          RhythmLane(
            grid: _dDuUdU(),
            chord: 'Em',
            fretting: FrettingState.unconfirmed,
          ),
        ),
      );
      // Eight slots: six struck, two ghosted — the ghosts are DRAWN, because the
      // hand travels through them.
      expect(find.byType(SsStrumGlyph), findsNWidgets(8));
    });

    testWidgets('the count row reads 1 & 2 & 3 & 4 &', (tester) async {
      await tester.pumpWidget(
        _host(
          RhythmLane(
            grid: _dDuUdU(),
            chord: 'Em',
            fretting: FrettingState.unconfirmed,
          ),
        ),
      );
      for (final beat in ['1', '2', '3', '4']) {
        expect(find.text(beat), findsOneWidget);
      }
      expect(find.text('&'), findsNWidgets(4));
    });

    testWidgets('a quarter grid counts 1 2 3 4 with no "&"', (tester) async {
      await tester.pumpWidget(
        _host(
          RhythmLane(
            grid: _mutedQuarters(),
            chord: null,
            fretting: FrettingState.unconfirmed,
          ),
        ),
      );
      expect(find.text('&'), findsNothing);
      expect(find.byType(SsStrumGlyph), findsNWidgets(4));
    });

    testWidgets('a ghost stroke is announced as a ghost, not as a stroke', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          RhythmLane(
            grid: _dDuUdU(),
            chord: 'Em',
            fretting: FrettingState.unconfirmed,
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(
          'ghost stroke, the hand passes without touching the strings',
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('each struck slot names its beat and direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          RhythmLane(
            grid: _dDuUdU(),
            chord: 'Em',
            fretting: FrettingState.unconfirmed,
          ),
        ),
      );
      expect(find.bySemanticsLabel('Beat 1, down stroke'), findsOneWidget);
      expect(find.bySemanticsLabel('Beat &, up stroke'), findsNWidgets(3));
    });
  });

  group('localisation', () {
    testWidgets('Hungarian renders its own strings, not the English ones', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          RhythmLane(
            grid: _mutedQuarters(),
            chord: null,
            fretting: FrettingState.unconfirmed,
          ),
          locale: const Locale('hu'),
        ),
      );
      expect(
        find.text('Nincs akkord — tompítsd a húrokat, csak a jobb kéz'),
        findsOneWidget,
      );
    });
  });

  group('the preparation window', () {
    testWidgets('marked slots get an underline, not only a tint', (
      tester,
    ) async {
      // The cue has to survive a greyscale screenshot, so it is a border too.
      final colors = SsDarkTheme.data().extension<SsColorScheme>()!;
      await tester.pumpWidget(
        _host(
          RhythmLane(
            grid: _dDuUdU(),
            chord: 'Em',
            fretting: FrettingState.unconfirmed,
            prepareSlotIndexes: const {6, 7},
          ),
        ),
      );
      final underlined = tester
          .widgetList<Container>(find.byType(Container))
          .where((container) {
            final decoration = container.decoration;
            if (decoration is! BoxDecoration) return false;
            final border = decoration.border;
            return border is Border && border.bottom.color == colors.info;
          });
      expect(underlined.length, 2);
    });
  });
}
