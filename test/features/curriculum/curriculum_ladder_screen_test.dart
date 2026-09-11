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
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/curriculum/domain/device_capabilities.dart';
import 'package:strumsight/features/curriculum/presentation/screens/curriculum_ladder_screen.dart';
import 'package:strumsight/features/curriculum/presentation/screens/rhythm_practice_screen.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/curriculum/application/curriculum_progress.dart';
import 'package:strumsight/features/curriculum/data/beginner_course.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_grading.dart';
import 'package:strumsight/features/curriculum/presentation/providers/curriculum_progress_providers.dart';
import 'package:strumsight/features/live/public.dart';
import 'package:strumsight/features/practice_generator/public.dart'
    show InMemoryPracticeEvidenceRepository;
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

Widget _host(
  Stream<LiveFrame> frames, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    liveFrameProvider.overrideWith((ref) => frames),
    keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
    ...overrides,
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: SsDarkTheme.data(),
    home: const CurriculumLadderScreen(),
  ),
);

/// A progress service whose store has already been played into, so the ladder
/// can be rendered for a learner with real measured evidence.
///
/// The attempts are placed a day apart on a FIXED clock: the reducer buckets
/// evidence by `measuredAt`, and identical instants would read as one
/// disagreeing bucket instead of a series.
Override _playedInto({
  required String missionId,
  required int attempts,
  bool flipDirection = false,
}) {
  final course = beginnerCourse();
  final mission = course.missionsInOrder.firstWhere(
    (candidate) => candidate.missionId == missionId,
  );
  final progress = CurriculumProgress(
    evidenceRepository: InMemoryPracticeEvidenceRepository(),
  );
  final grid = mission.rhythm!.grid;
  final bpm = mission.rhythm!.bpm;
  for (var i = 0; i < attempts; i++) {
    progress.recordRhythmAttempt(
      mission: mission,
      attempt: gradeRhythm(
        grid,
        bpm: bpm,
        bars: mission.rhythm!.bars,
        strokes: [
          for (var bar = 0; bar < mission.rhythm!.bars; bar++)
            for (final slot in grid.slots)
              if (slot.isStruck)
                DetectedStroke(
                  atUs: grid.onsetUs(bar: bar, slotIndex: slot.index, bpm: bpm),
                  direction: flipDirection
                      ? (slot.direction == StrumDirection.down
                            ? StrumDirection.up
                            : StrumDirection.down)
                      : slot.direction,
                  isConfirmed: true,
                ),
        ],
      ),
      at: _fixedNow.subtract(Duration(days: attempts - i)),
    );
  }
  return curriculumProgressProvider.overrideWithValue(progress);
}

final DateTime _fixedNow = DateTime.utc(2026, 9, 12, 10);

final Override _fixedClock = curriculumClockProvider.overrideWithValue(
  () => _fixedNow,
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

  testWidgets('a locked rung names what it needs, in words', (tester) async {
    await tester.pumpWidget(_host(Stream<LiveFrame>.value(_frame())));
    await tester.pump();
    // "Locked" on its own tells the learner nothing they can act on — and
    // "Needs first: rhythm.downQuarters" tells them nothing either.
    expect(
      find.textContaining('Needs first: steady down-strokes'),
      findsWidgets,
    );
  });

  testWidgets('nothing on the ladder is a persistence code', (tester) async {
    await tester.pumpWidget(_host(Stream<LiveFrame>.value(_frame())));
    await tester.pump();

    // The ids are deliberately stable and deliberately never translated, which is
    // exactly what makes them wrong on screen. Scanning every rendered string is
    // cheaper than one cell per id and it cannot be outgrown by a new rung.
    final scroll = find.byType(Scrollable).first;
    for (var sweep = 0; sweep < 12; sweep++) {
      for (final widget in tester.widgetList<Text>(find.byType(Text))) {
        final shown = widget.data;
        if (shown == null) continue;
        for (final prefix in const [
          'mission.',
          'level.',
          'stage.',
          'chord.',
          'rhythm.',
          'strumPattern.',
          'songPerformance.',
        ]) {
          expect(
            shown.contains(prefix),
            isFalse,
            reason: 'a persistence code reached the screen: "$shown"',
          );
        }
      }
      await tester.drag(scroll, const Offset(0, -300));
      await tester.pump();
    }
  });

  testWidgets('each rung is numbered once, in ladder order', (tester) async {
    await tester.pumpWidget(_host(Stream<LiveFrame>.value(_frame())));
    await tester.pump();
    // The order IS the teaching sequence, so the number is information. Step 1
    // must be the first rung of the first stage, and no number may repeat.
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('Step 2'), findsOneWidget);
    expect(find.text('First sounds'), findsOneWidget);
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

  group('what the ladder says about measured progress', () {
    testWidgets(
      'a learner who has played nothing sees no attempt count — not a '
      'zero',
      (tester) async {
        await tester.pumpWidget(_host(Stream<LiveFrame>.value(_frame())));
        await tester.pump();
        expect(
          find.textContaining('Measured over'),
          findsNothing,
          reason:
              'absence of evidence is not a low score, and "0 attempts" would '
              'read as one',
        );
      },
    );

    testWidgets('two clean attempts open the next rung and the count says what '
        'the verdict rests on', (tester) async {
      await tester.pumpWidget(
        _host(
          Stream<LiveFrame>.value(_frame()),
          overrides: [
            _fixedClock,
            _playedInto(missionId: 'mission.downQuarters', attempts: 2),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Measured over 2 attempts'), findsOneWidget);

      // `mission.downUpEighths` is gated on exactly the skill just measured, so
      // its own row must now read as open. Asserted on THAT row rather than on a
      // count of "Open" labels: a count would pass just as happily if some other
      // rung had opened instead, which is the opposite of what this measures.
      // It is also below the fold, and a row the ListView never built is a row
      // this test would never see.
      await tester.scrollUntilVisible(
        find.text('Down-up eighths'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Down-up eighths'),
            matching: find.byType(ListTile),
          ),
          matching: find.text('Open'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a learner who strummed everything the WRONG way is never '
        'praised', (tester) async {
      // The regression guard for what `curriculum_progress_test.dart` measured:
      // six confirmed wrong-direction attempts reduce to SkillEstimateState
      // `stable` at level 0.000, so any wording derived from the state would
      // have put a word like "Steady" or "Solid" on screen.
      await tester.pumpWidget(
        _host(
          Stream<LiveFrame>.value(_frame()),
          overrides: [
            _fixedClock,
            _playedInto(
              missionId: 'mission.downQuarters',
              attempts: 6,
              flipDirection: true,
            ),
          ],
        ),
      );
      await tester.pump();

      // Asserted as the EXACT set of strings the row is allowed to say, rather
      // than as a list of forbidden words. A word list was the first version and
      // it was wrong twice over: "Steady down-strokes" is now the legitimate NAME
      // of this very exercise, so banning "Steady" banned the row's own title;
      // and a banned-word list would have missed any new wording a later round
      // invented. An exact set catches an extra line however it is phrased.
      final row = find.ancestor(
        of: find.text('Steady down-strokes'),
        matching: find.byType(ListTile),
      );
      final shown = tester
          .widgetList<Text>(
            find.descendant(of: row, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .whereType<String>()
          .toSet();
      expect(
        shown,
        {'Steady down-strokes', 'Step 2', 'Open', 'Measured over 6 attempts'},
        reason:
            'six confirmed wrong-direction attempts reduce to state `stable` at '
            'level 0.000, so ANY extra line derived from the state would be '
            'praise for playing every stroke backwards',
      );
      // And nothing it measured opened a gated rung: the level is 0.0.
      expect(find.text('Not yet reached'), findsWidgets);
    });
  });

  testWidgets('Hungarian renders Hungarian', (tester) async {
    await tester.pumpWidget(
      _host(Stream<LiveFrame>.value(_frame()), locale: const Locale('hu')),
    );
    await tester.pump();
    expect(find.text('A te utad'), findsOneWidget);
  });
}
