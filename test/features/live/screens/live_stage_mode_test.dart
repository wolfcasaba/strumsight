// E14-R37 (ADR 0550) — the Live stage's PRODUCT mode.
//
// Three things are pinned here, and only these three:
//   1. Free play is the default and it LOOKS like free play — no target
//      anywhere on the stage.
//   2. Guided shows the expected chord as a TARGET: labelled with its role,
//      spoken role-first, and never inside the detection hero.
//   3. The Live screen never hands the engine an expected-chord LABEL. It
//      makes exactly one `setExpectedChord` call, and that call is `null`
//      (ADR 0544 D2 makes the label inert anyway; this pins that Live does
//      not even try).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_mode.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/providers/live_stage_mode.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/live/widgets/guided_target_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_engines.dart';
import '../../../support/preference_store.dart';

LiveFrame _frame({Chord? current}) => LiveFrame(
  current: current,
  next: null,
  latestStrum: null,
  bar: const [],
  bpm: 96,
  inputLevel: 0.6,
  tuningHz: 440,
  listening: true,
  engineTimeSec: 1.0,
  chordDecision: current == null ? null : RecognitionDecision.confirmed,
);

Future<FakeStrumEngine> _pumpLive(
  WidgetTester tester, {
  String? guidedTarget,
}) async {
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        ...fakeAudioOverrides(),
        strumEngineProvider.overrideWithValue(engine),
        if (guidedTarget != null)
          liveGuidedTargetProvider.overrideWith(
            () => _FixedGuidedTarget(guidedTarget),
          ),
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
  return engine;
}

class _FixedGuidedTarget extends LiveGuidedTargetController {
  _FixedGuidedTarget(this._label);

  final String _label;

  @override
  String? build() => _label;
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('the engine regime is declared, not implied', () {
    test('the shipped regime is free — the fail-closed value', () {
      final container = ProviderContainer(
        overrides: [...preferenceOverrides(), ...fakeAudioOverrides()],
      );
      addTearDown(container.dispose);
      expect(container.read(liveRecognitionModeProvider), RecognitionMode.free);
      expect(
        container.read(liveRecognitionModeProvider).allowsExpectedChordPrior,
        isFalse,
        reason: 'a free engine cannot even BUILD an expected-chord hint',
      );
    });
  });

  group('free play (the default)', () {
    testWidgets('names itself and shows no target at all', (tester) async {
      final engine = await _pumpLive(tester);
      engine.emit(_frame(current: const Chord('C')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.liveModeFreePlay), findsOneWidget);
      expect(find.text(l10n.liveModeGuided), findsNothing);
      expect(find.byType(GuidedTargetCard), findsNothing);
      expect(find.text(l10n.liveGuidedTarget.toUpperCase()), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
      'Live never hands the engine an expected-chord LABEL — every call it '
      'makes is a clear',
      (tester) async {
        final engine = await _pumpLive(tester);
        engine.emit(_frame(current: const Chord('C')));
        await tester.pumpAndSettle();
        engine.emit(_frame(current: const Chord('G')));
        await tester.pumpAndSettle();

        expect(engine.expectedChordCalls, isNotEmpty);
        expect(
          engine.expectedChordCalls.every((label) => label == null),
          isTrue,
          reason:
              'a non-null label from the free-play screen would be a '
              'lesson bias leaking into free play: '
              '${engine.expectedChordCalls}',
        );
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('guided', () {
    testWidgets('names itself and renders the target AS a target', (
      tester,
    ) async {
      final engine = await _pumpLive(tester, guidedTarget: 'Am');
      engine.emit(_frame(current: null));
      await tester.pumpAndSettle();

      expect(find.text(l10n.liveModeGuided), findsOneWidget);
      expect(find.text(l10n.liveModeFreePlay), findsNothing);
      expect(find.byType(GuidedTargetCard), findsOneWidget);
      // Role BEFORE value, in words, for both sighted and screen-reader use.
      expect(find.text(l10n.liveGuidedTarget.toUpperCase()), findsOneWidget);
      expect(
        find.bySemanticsLabel(l10n.liveGuidedTargetSemantics('Am')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
      'the target is NEVER presented as a detection: with nothing heard, no '
      'chord hero exists even though a target is on screen',
      (tester) async {
        final engine = await _pumpLive(tester, guidedTarget: 'Am');
        engine.emit(_frame(current: null));
        await tester.pumpAndSettle();

        expect(find.byType(GuidedTargetCard), findsOneWidget);
        expect(
          find.byType(SsChordHero),
          findsNothing,
          reason:
              'the hero is the DETECTION slot; a target rendered there '
              'would read as "we heard Am"',
        );
        await tester.pump(const Duration(milliseconds: 400));
      },
    );

    testWidgets(
      'a guided target does not change what the detector claims: the hero '
      'still shows the chord that was actually heard',
      (tester) async {
        final engine = await _pumpLive(tester, guidedTarget: 'Am');
        engine.emit(_frame(current: const Chord('C')));
        await tester.pumpAndSettle();

        final hero = tester.widget<SsChordHero>(find.byType(SsChordHero));
        expect(hero.chordLabel, 'C');
        expect(find.byType(GuidedTargetCard), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('the stage mode is derived from the target, never stored twice', () {
    test('no target → free play; a target → guided; cleared → free play', () {
      final container = ProviderContainer(
        overrides: [...preferenceOverrides(), ...fakeAudioOverrides()],
      );
      addTearDown(container.dispose);

      expect(container.read(liveStageModeProvider), LiveStageMode.freePlay);
      container.read(liveGuidedTargetProvider.notifier).set('D');
      expect(container.read(liveStageModeProvider), LiveStageMode.guided);
      container.read(liveGuidedTargetProvider.notifier).clear();
      expect(container.read(liveStageModeProvider), LiveStageMode.freePlay);
      // An empty label is not a target.
      container.read(liveGuidedTargetProvider.notifier).set('');
      expect(container.read(liveStageModeProvider), LiveStageMode.freePlay);
    });
  });
}
