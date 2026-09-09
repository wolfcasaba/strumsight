// E14-R39 (ADR 0547) — reduced motion on the beat pulse and on the Live
// chord feedback.
//
// The design system's own `SsBeatPulse` has honoured reduced motion since
// ADR 0274; the audit's finding was that the SHIPPED pulses did not — only
// the component knew the rule. This file drives the shipped widgets through
// their public API and pins the rule where it now holds, and pins the part
// that survives (content, not motion) where it does not yet.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/chord_event.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/live/widgets/chord_timeline.dart';
import 'package:strumsight/features/metronome/beat_pulse_dot.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../support/preference_store.dart';

final class _FakeBeatClock implements SsBeatClock {
  _FakeBeatClock([this.position]);

  @override
  Duration? position;
}

const _beat = Duration(milliseconds: 1000);
const _onBeat = Duration(milliseconds: 100);
const _offBeat = Duration(milliseconds: 700);
const _dotColor = Color(0xFFD98A46);
const _mutedColor = Color(0xFF948D82);

/// The metronome dot under an explicit app-level reduced-motion override.
Widget _dot(_FakeBeatClock clock, {required bool? reduceMotion}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SsMotionScope(
        appOverride: reduceMotion,
        child: BeatPulseDot(
          playing: true,
          clock: clock,
          beatDuration: _beat,
          color: _dotColor,
          mutedColor: _mutedColor,
        ),
      ),
    ),
  ),
);

/// The same dot with NO app override, so the platform accessibility setting
/// alone decides — the cell that proves the widget reads the system switch
/// and not merely a StrumSight-only preference.
Widget _dotWithSystemSetting(
  _FakeBeatClock clock, {
  required bool disableAnimations,
}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: BeatPulseDot(
            playing: true,
            clock: clock,
            beatDuration: _beat,
            color: _dotColor,
            mutedColor: _mutedColor,
          ),
        ),
      ),
    ),
  ),
);

Color? _dotDecorationColor(WidgetTester tester) =>
    (tester.widget<Container>(find.byKey(BeatPulseDot.dotKey)).decoration
            as BoxDecoration)
        .color;

Future<void> _pumpLive(WidgetTester tester, Widget child) => tester.pumpWidget(
  ProviderScope(
    overrides: preferenceOverrides(),
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

ChordEvent _event(String label, int seq) => ChordEvent(
  chord: Chord(label),
  direction: StrumDirection.down,
  confidence: 0.8,
  seq: seq,
  timeSec: seq.toDouble(),
);

void main() {
  group('the metronome beat pulse honours reduced motion', () {
    testWidgets(
      'full motion: the dot really does scale with the beat phase — the '
      'falsification cell, without which "no scale" below proves nothing',
      (tester) async {
        final clock = _FakeBeatClock(_onBeat);
        await tester.pumpWidget(_dot(clock, reduceMotion: false));
        await tester.pump();
        final onBeat = tester.getSize(find.byKey(BeatPulseDot.dotKey));

        clock.position = _offBeat;
        await tester.pump();
        final offBeat = tester.getSize(find.byKey(BeatPulseDot.dotKey));

        expect(offBeat, isNot(onBeat));
      },
    );

    testWidgets(
      'reduced motion: no scale, but the pulse still steps with the beat — '
      'it is functional feedback, so it is de-animated, never removed',
      (tester) async {
        final clock = _FakeBeatClock(_onBeat);
        await tester.pumpWidget(_dot(clock, reduceMotion: true));
        await tester.pump();
        final onBeatSize = tester.getSize(find.byKey(BeatPulseDot.dotKey));
        final onBeatColor = _dotDecorationColor(tester);

        clock.position = _offBeat;
        await tester.pump();
        final offBeatSize = tester.getSize(find.byKey(BeatPulseDot.dotKey));
        final offBeatColor = _dotDecorationColor(tester);

        expect(onBeatSize, const Size(16, 16), reason: 'base size, unscaled');
        expect(offBeatSize, onBeatSize, reason: 'still no scale');
        expect(
          offBeatColor,
          isNot(onBeatColor),
          reason: 'the channel that replaces scale must still track the beat',
        );
        expect(
          offBeatColor,
          isNot(_mutedColor),
          reason:
              'the off-beat half must not be pixel-identical to "stopped" — '
              'that would make a running metronome look idle for half of '
              'every beat',
        );
      },
    );

    testWidgets(
      'the PLATFORM setting alone is enough — no app-level override needed',
      (tester) async {
        final clock = _FakeBeatClock(_onBeat);
        await tester.pumpWidget(
          _dotWithSystemSetting(clock, disableAnimations: true),
        );
        await tester.pump();
        final onBeat = tester.getSize(find.byKey(BeatPulseDot.dotKey));

        clock.position = _offBeat;
        await tester.pump();

        expect(onBeat, const Size(16, 16));
        expect(tester.getSize(find.byKey(BeatPulseDot.dotKey)), onBeat);
      },
    );

    testWidgets('a stopped metronome renders the muted dot at base size', (
      tester,
    ) async {
      final clock = _FakeBeatClock(_onBeat);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BeatPulseDot(
                playing: false,
                clock: clock,
                beatDuration: _beat,
                color: _dotColor,
                mutedColor: _mutedColor,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(BeatPulseDot.dotKey)),
        const Size(16, 16),
      );
      expect(_dotDecorationColor(tester), _mutedColor);
    });
  });

  // MEASURED GAP (docs/accessibility/ch14-r39-audit.md): the Live hero's
  // per-beat `flutter_animate` scale pulse in `chord_timeline.dart` has no
  // reduced-motion branch — the widget is PKG-F's, so this round pins only
  // what is true today: under reduced motion the chord INFORMATION is never
  // lost and the tree still settles. The scale-suppression assertion ships
  // together with the proposed patch (round brief §10), not before it.
  group('the Live chord timeline under reduced motion', () {
    testWidgets(
      'the recognised chord stays fully readable and the tree settles when '
      'animations are disabled',
      (tester) async {
        await _pumpLive(
          tester,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: ChordTimeline(
                events: [_event('G', 1), _event('C', 2)],
                capo: 0,
                beat: 3,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('C'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
