// The course, made visible.
//
// The cells here are about the three availability states reading HONESTLY, which
// is the whole reason the domain distinguishes them:
//
//   - a locked rung must not read as a failure, and must say what it needs;
//   - an unmeasurable rung must read as the DEVICE's limit, naming what is
//     missing, not as the learner's shortfall;
//   - an open rung must start the mission it offered, not a default.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/curriculum/domain/device_capabilities.dart';
import 'package:strumsight/features/curriculum/presentation/screens/curriculum_ladder_screen.dart';
import 'package:strumsight/features/curriculum/presentation/screens/rhythm_practice_screen.dart';
import 'package:strumsight/features/live/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/features/practice_generator/public.dart'
    show CapabilitySupport, ExerciseCapability;

import '../../core/storage/in_memory_key_value_store.dart';

LiveFrame _frame({bool listening = true}) => LiveFrame(
  current: null,
  next: null,
  latestStrum: null,
  bar: const [],
  bpm: 0,
  inputLevel: 0.4,
  tuningHz: 440,
  listening: listening,
  engineTimeSec: 1.0,
  latestStrumTime: -1,
  strumSeq: 0,
);

Widget _host(Stream<LiveFrame> frames, {Locale locale = const Locale('en')}) =>
    ProviderScope(
      overrides: [
        liveFrameProvider.overrideWith((ref) => frames),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: SsDarkTheme.data(),
        home: const CurriculumLadderScreen(),
      ),
    );

void main() {
  group('the capability map is conservative by construction', () {
    test('nothing audio-dependent is claimed while no audio arrives', () {
      final capabilities = curriculumDeviceCapabilities(
        microphoneListening: false,
      );
      for (final capability in [
        ExerciseCapability.requiresMicrophone,
        ExerciseCapability.supportsDirectionScoring,
        ExerciseCapability.supportsChordScoring,
        ExerciseCapability.supportsTempo,
      ]) {
        expect(
          capabilities[capability],
          isNot(CapabilitySupport.supported),
          reason:
              '$capability cannot be claimed with no audio — claiming it would '
              'hand the learner a score that means nothing',
        );
      }
    });

    test('the scoring capabilities arrive with the audio', () {
      final capabilities = curriculumDeviceCapabilities(
        microphoneListening: true,
      );
      expect(
        capabilities[ExerciseCapability.supportsDirectionScoring],
        CapabilitySupport.supported,
      );
      expect(
        capabilities[ExerciseCapability.supportsChordScoring],
        CapabilitySupport.supported,
      );
    });

    test('pitch scoring and camera are never claimed', () {
      // Neither has evidence behind it in this app: no exercise has ever been
      // scored on pitch here, and there is no camera-based scoring at all.
      for (final listening in [false, true]) {
        final capabilities = curriculumDeviceCapabilities(
          microphoneListening: listening,
        );
        expect(
          capabilities[ExerciseCapability.supportsPitchScoring],
          isNot(CapabilitySupport.supported),
        );
        expect(
          capabilities[ExerciseCapability.requiresCamera],
          isNot(CapabilitySupport.supported),
        );
      }
    });

    test('the offline claim holds with or without audio', () {
      // The recognition path is on-device DSP; it does not depend on the mic
      // being live, and it must not flicker with it.
      for (final listening in [false, true]) {
        expect(
          curriculumDeviceCapabilities(
            microphoneListening: listening,
          )[ExerciseCapability.supportsOffline],
          CapabilitySupport.supported,
        );
      }
    });
  });

  testWidgets('the ladder renders the course, open rungs first', (
    tester,
  ) async {
    await tester.pumpWidget(_host(Stream<LiveFrame>.value(_frame())));
    await tester.pump();
    expect(find.text('Your path'), findsOneWidget);
    // The first two rungs are `UnlockRule.always`, so with no measured skills
    // they are the ones that read as open.
    expect(find.text('Open'), findsWidgets);
  });

  testWidgets('a locked rung reads as NOT YET, never as a failure', (
    tester,
  ) async {
    await tester.pumpWidget(_host(Stream<LiveFrame>.value(_frame())));
    await tester.pump();
    // Design §2 rule 6: a mission cannot fail, it can only be not yet reached.
    expect(find.text('Not yet reached'), findsWidgets);
    for (final forbidden in ['Failed', 'failed', 'Locked', 'locked']) {
      expect(
        find.textContaining(forbidden),
        findsNothing,
        reason: 'a rung that has not opened is not a failure: "$forbidden"',
      );
    }
  });

  testWidgets('a locked rung names what it needs', (tester) async {
    await tester.pumpWidget(_host(Stream<LiveFrame>.value(_frame())));
    await tester.pump();
    // "Locked" on its own tells the learner nothing they can act on.
    expect(find.textContaining('Needs first:'), findsWidgets);
  });

  testWidgets('with no audio, unmeasurable rungs blame the DEVICE and say what '
      'is missing', (tester) async {
    final controller = StreamController<LiveFrame>();
    addTearDown(controller.close);
    await tester.pumpWidget(_host(controller.stream));
    await tester.pump();
    controller.add(_frame(listening: false));
    await tester.pump();

    expect(
      find.text('This device cannot measure this one'),
      findsWidgets,
      reason: 'the scoring rungs are unmeasurable without audio',
    );
    // Named in words a learner can act on, not as the enum's persistence code.
    expect(find.textContaining('Missing:'), findsWidgets);
    expect(
      find.textContaining('supportsChordScoring'),
      findsNothing,
      reason: 'a persistence token is not a sentence',
    );
  });

  testWidgets('an open rung opens THAT mission, not the default', (
    tester,
  ) async {
    await tester.pumpWidget(_host(Stream<LiveFrame>.value(_frame())));
    await tester.pump();

    final openable = find.byIcon(Icons.play_arrow);
    expect(openable, findsWidgets);
    await tester.tap(openable.first);
    // Not `pumpAndSettle`: the rhythm screen runs a Ticker for the pendulum, so
    // the tree never goes quiescent and settling times out. Pumping past the
    // route transition is what this cell actually needs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final screen = tester.widget<RhythmPracticeScreen>(
      find.byType(RhythmPracticeScreen),
    );
    expect(
      screen.mission,
      isNotNull,
      reason:
          'offering a rung and then starting a different one would be the '
          'ladder lying about what it just offered',
    );
  });

  testWidgets('Hungarian renders Hungarian', (tester) async {
    await tester.pumpWidget(
      _host(Stream<LiveFrame>.value(_frame()), locale: const Locale('hu')),
    );
    await tester.pump();
    expect(find.text('A te utad'), findsOneWidget);
  });
}
