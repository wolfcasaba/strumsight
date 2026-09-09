// E14-R37 (ADR 0550) — the Live stage's honesty on the DECISION axis.
//
// `live_screen_truthfulness_test.dart` pins the REJECT-REASON axis (ADR 0520
// / 0535): why nothing was recognised. This file pins the other axis of the
// same contract (ADR 0505 D3): WHICH decision state the recognizer is in.
//
//   1. All six states render, and all six render DISTINCTLY — no two of them
//      collapse to the same sentence.
//   2. Only `confirmed` lets a chord reach the detection hero. A frame that
//      carries a chord under any other decision must not present it: that is
//      exactly "weak confidence rendered as a confident claim" (AGENTS.md §5).
//   3. The wave-2 signal gate is KEPT: under a `signal*` reject there is no
//      strum direction and no tempo claim.
//   4. The new states survive the hard layouts — 360 px portrait, landscape,
//      and textScale 2.0 — without overflowing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/model/beat_slot.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/live/widgets/recognition_state_chip.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_engines.dart';
import '../../../support/preference_store.dart';

const _downStrum = Strum(direction: StrumDirection.down, confidence: 0.9);

LiveFrame _frame({
  Chord? current = const Chord('C'),
  Strum? latestStrum,
  RecognitionDecision? decision,
  RecognitionRejectReason? rejectReason,
  double bpm = 120,
}) => LiveFrame(
  current: current,
  next: null,
  latestStrum: latestStrum,
  bar: [
    BeatSlot(label: '1', isDownbeat: true, strum: latestStrum),
    const BeatSlot(label: '&', isDownbeat: false),
  ],
  bpm: bpm,
  inputLevel: 0.6,
  tuningHz: 440,
  listening: true,
  strumSeq: latestStrum == null ? 0 : 1,
  latestStrumTime: latestStrum == null ? -1 : 9.5,
  engineTimeSec: 10,
  chordDecision: decision,
  chordRejectReason: rejectReason,
);

Future<FakeStrumEngine> _pumpLive(
  WidgetTester tester, {
  Size? viewport,
  double textScale = 1.0,
}) async {
  if (viewport != null) {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        ...fakeAudioOverrides(),
        strumEngineProvider.overrideWithValue(engine),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const LiveScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return engine;
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('all six decision states are distinct', () {
    test('no two states share a sentence — the anti-collapse guard', () {
      final texts = <String>{
        for (final decision in RecognitionDecision.values)
          RecognitionStateChip.textFor(l10n, decision, 'C'),
      };
      expect(
        texts,
        hasLength(RecognitionDecision.values.length),
        reason: 'two decision states rendering the same words is the same '
            'failure ADR 0535 removed from the reject-reason axis',
      );
      for (final text in texts) {
        expect(text.trim(), isNotEmpty);
      }
    });

    test('every state has its own glyph, so full colour loss keeps them '
        'apart (E14-R39 lelet: the confidence tokens are one grey)', () {
      final icons = <int>{
        for (final decision in RecognitionDecision.values)
          RecognitionStateChip.iconFor(decision).codePoint,
      };
      expect(icons, hasLength(RecognitionDecision.values.length));
    });

    test('provisional hedges: it names the chord only inside a hedged '
        'sentence, and degrades when no chord is known', () {
      final named = RecognitionStateChip.textFor(
        l10n,
        RecognitionDecision.provisional,
        'C',
      );
      final unnamed = RecognitionStateChip.textFor(
        l10n,
        RecognitionDecision.provisional,
        null,
      );
      expect(named, contains('C'));
      expect(named, isNot(equals('C')));
      expect(unnamed, isNot(contains('C')));
      expect(
        RecognitionStateChip.textFor(l10n, RecognitionDecision.provisional, ''),
        unnamed,
      );
    });

    for (final decision in RecognitionDecision.values) {
      testWidgets('${decision.name} reaches the real LiveScreen and states '
          'itself', (tester) async {
        final engine = await _pumpLive(tester);
        engine.emit(_frame(current: null, decision: decision));
        await tester.pumpAndSettle();

        expect(
          find.text(RecognitionStateChip.textFor(l10n, decision, null)),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 400));
      });
    }
  });

  group('only a confirmed decision may present a chord', () {
    testWidgets('confirmed → the hero shows the chord', (tester) async {
      final engine = await _pumpLive(tester);
      engine.emit(
        _frame(
          current: const Chord('C'),
          decision: RecognitionDecision.confirmed,
        ),
      );
      await tester.pumpAndSettle();

      final hero = tester.widget<SsChordHero>(find.byType(SsChordHero));
      expect(hero.chordLabel, 'C');
      await tester.pump(const Duration(milliseconds: 400));
    });

    for (final decision in const [
      RecognitionDecision.candidate,
      RecognitionDecision.provisional,
      RecognitionDecision.uncertain,
      RecognitionDecision.rejected,
      RecognitionDecision.expired,
    ]) {
      testWidgets(
        '${decision.name} → the chord is NOT presented as recognised, even '
        'though the frame carries one',
        (tester) async {
          final engine = await _pumpLive(tester);
          engine.emit(
            _frame(current: const Chord('C'), decision: decision),
          );
          await tester.pumpAndSettle();

          expect(
            find.byType(SsChordHero),
            findsNothing,
            reason: 'the hero is the "we heard this" slot; a chord under a '
                '${decision.name} verdict is not a claim the engine makes',
          );
          await tester.pump(const Duration(milliseconds: 400));
        },
      );
    }

    testWidgets(
      'a producer with NO typed decision keeps the pre-E14-R37 behaviour — '
      'this round invents no verdict for mocks and adapters',
      (tester) async {
        final engine = await _pumpLive(tester);
        engine.emit(_frame(current: const Chord('G')));
        await tester.pumpAndSettle();

        final hero = tester.widget<SsChordHero>(find.byType(SsChordHero));
        expect(hero.chordLabel, 'G');
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('the signal gate is kept (wave-2 audit H9)', () {
    testWidgets(
      'a signal* reject claims neither a strum direction nor a tempo, and '
      'the decision chip says there is no reading',
      (tester) async {
        final engine = await _pumpLive(tester);
        engine.emit(
          _frame(
            current: null,
            latestStrum: _downStrum,
            decision: RecognitionDecision.rejected,
            rejectReason: RecognitionRejectReason.signalTooQuiet,
            bpm: 133,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('133 BPM'), findsNothing);
        expect(
          find.textContaining(l10n.liveTempoNotMeasured),
          findsOneWidget,
        );
        expect(find.byType(SsChordHero), findsNothing);
        expect(
          find.text(
            RecognitionStateChip.textFor(
              l10n,
              RecognitionDecision.rejected,
              null,
            ),
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('hard layouts — the new states must not overflow', () {
    const cases = <String, Size>{
      '360 px portrait (the narrowest supported phone)': Size(360, 640),
      'compact portrait 412': Size(412, 915),
      'landscape 915 × 412': Size(915, 412),
    };

    for (final MapEntry(key: name, value: size) in cases.entries) {
      for (final textScale in const [1.0, 2.0]) {
        testWidgets('$name @ textScale $textScale — uncertain + reject '
            'banner + guided-less mode chip all fit', (tester) async {
          final engine = await _pumpLive(
            tester,
            viewport: size,
            textScale: textScale,
          );
          engine.emit(
            _frame(
              current: null,
              decision: RecognitionDecision.uncertain,
              rejectReason: RecognitionRejectReason.lowConfidence,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: '$name @ $textScale overflowed',
          );
          await tester.pump(const Duration(milliseconds: 400));
        });
      }
    }
  });
}
