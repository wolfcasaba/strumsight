// Audit fixes H9/H10/H19 — what the Live screen is allowed to CLAIM:
//   H9  — while the merged recognizer rejects the frame for a SIGNAL reason
//         (the six `signal*` reasons, ADR 0535 D1) the screen may not present
//         a strum direction or a tempo as a measurement. It has just said it
//         cannot tell what it is hearing (AGENTS.md §5).
//   H10 — a strum indicator EXPIRES: 2 s without a fresh detection and the
//         arrow is gone, in silence too.
//   H19 — "0 BPM" is the ABSENCE of a tempo, not a tempo of zero. Say so.
//
// The model group pins the rules exactly; the screen group proves the real
// LiveScreen obeys them.
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
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

const _downStrum = Strum(direction: StrumDirection.down, confidence: 0.9);

LiveFrame _frame({
  Chord? current = const Chord('C'),
  Strum? latestStrum = _downStrum,
  double bpm = 133,
  double engineTimeSec = 10,
  double latestStrumTime = 9.5,
  RecognitionRejectReason? chordRejectReason,
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
  strumSeq: 1,
  latestStrumTime: latestStrum == null ? -1 : latestStrumTime,
  engineTimeSec: engineTimeSec,
  chordRejectReason: chordRejectReason,
);

Future<void> _pumpLive(WidgetTester tester, FakeStrumEngine engine) async {
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
        home: const LiveScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('LiveFrame — what may be shown', () {
    test('every signal* reject reason marks the signal unusable', () {
      const signalReasons = <RecognitionRejectReason>[
        RecognitionRejectReason.signalTooQuiet,
        RecognitionRejectReason.signalTooLoud,
        RecognitionRejectReason.signalClipping,
        RecognitionRejectReason.signalTooNoisy,
        RecognitionRejectReason.signalSpeechLike,
        RecognitionRejectReason.signalUnstable,
      ];
      for (final reason in signalReasons) {
        final frame = _frame(chordRejectReason: reason);
        expect(frame.hasUnusableSignal, isTrue, reason: reason.name);
        expect(frame.displayStrum, isNull, reason: reason.name);
        expect(frame.hasMeasuredTempo, isFalse, reason: reason.name);
        expect(
          frame.displayBar.every((slot) => slot.strum == null),
          isTrue,
          reason: reason.name,
        );
      }
    });

    test('a chord-level reject reason leaves the readings alone', () {
      for (final reason in const [
        RecognitionRejectReason.lowConfidence,
        RecognitionRejectReason.unstable,
        RecognitionRejectReason.noChord,
        RecognitionRejectReason.modelUnavailable,
        RecognitionRejectReason.timeout,
      ]) {
        final frame = _frame(chordRejectReason: reason);
        expect(frame.hasUnusableSignal, isFalse, reason: reason.name);
        expect(frame.displayStrum, isNotNull, reason: reason.name);
        expect(frame.hasMeasuredTempo, isTrue, reason: reason.name);
      }
    });

    test('a strum older than the 2 s hold window expires', () {
      final fresh = _frame(engineTimeSec: 10, latestStrumTime: 8.5);
      final stale = _frame(engineTimeSec: 10, latestStrumTime: 7.5);

      expect(fresh.strumExpired, isFalse);
      expect(fresh.displayStrum, isNotNull);
      expect(stale.strumExpired, isTrue);
      expect(stale.displayStrum, isNull);
      expect(stale.displayBar.every((slot) => slot.strum == null), isTrue);
    });

    test('a clock-less producer (mocks) can age nothing', () {
      final frame = _frame(engineTimeSec: -1, latestStrumTime: -1);
      expect(frame.strumExpired, isFalse);
      expect(frame.displayStrum, isNotNull);
    });

    test('zero BPM is the absence of a tempo, not a measured tempo', () {
      expect(_frame(bpm: 0).hasMeasuredTempo, isFalse);
      expect(_frame(bpm: 133).hasMeasuredTempo, isTrue);
    });
  });

  group('LiveScreen — the screen obeys those rules', () {
    testWidgets('a measured tempo and a fresh strum are shown', (tester) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);
      await _pumpLive(tester, engine);

      engine.emit(_frame());
      await tester.pumpAndSettle();

      expect(find.byType(SsStrumGlyph), findsWidgets);
      expect(find.textContaining('133 BPM'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
      'H9 — a signal* reject shows neither a strum arrow nor a tempo, while '
      'the banner states why',
      (tester) async {
        final engine = FakeStrumEngine();
        addTearDown(engine.dispose);
        await _pumpLive(tester, engine);

        engine.emit(
          _frame(chordRejectReason: RecognitionRejectReason.signalTooQuiet),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SsStrumGlyph), findsNothing);
        expect(find.textContaining('133 BPM'), findsNothing);
        expect(find.textContaining(l10n.liveTempoNotMeasured), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
      },
    );

    testWidgets('H10 — a strum older than 2 s disappears, silence or not', (
      tester,
    ) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);
      await _pumpLive(tester, engine);

      engine.emit(_frame(engineTimeSec: 10, latestStrumTime: 9.5));
      await tester.pumpAndSettle();
      expect(find.byType(SsStrumGlyph), findsWidgets);

      // Same strum, 2.5 s of silence later — the producer kept reporting it.
      engine.emit(_frame(engineTimeSec: 12, latestStrumTime: 9.5));
      await tester.pumpAndSettle();

      expect(
        find.byType(SsStrumGlyph),
        findsNothing,
        reason: 'an indicator expires without a fresh detection',
      );
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('H19 — an unmeasured tempo is stated, never printed as 0', (
      tester,
    ) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);
      await _pumpLive(tester, engine);

      engine.emit(_frame(bpm: 0));
      await tester.pumpAndSettle();

      expect(find.textContaining('0 BPM'), findsNothing);
      expect(find.textContaining(l10n.liveTempoNotMeasured), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
