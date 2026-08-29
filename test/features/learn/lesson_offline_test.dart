import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/chords/widgets/chord_diagram.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/learn/screens/learn_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../support/preference_store.dart';

/// A4 (ADR 0282 §Döntés 4 spirit, §0.0/R9) — this app has no downloadable
/// lesson asset (0 hits for `download`/`rootBundle` on this tree; lessons are
/// code constants and the backing is synthesized locally). The two REAL
/// missing-resource cases are: no diagram shape for a chord label
/// (`ChordShapes.forLabel == null`) and no synthesizable backing for an
/// unrecognised root (`ChordAudio.frequencies == null`). Neither must crash
/// or blank the screen — the gap is NAMED, and the lesson stays fully
/// playable, which is the real available next step.
Lesson _lessonWithUnknownChord() => Lesson.fromEvents(
  id: 'offline-probe',
  name: 'Offline probe',
  bpm: 80,
  totalBeats: 4,
  events: const [
    LessonEvent(beat: 0, chord: 'Xyz9', direction: StrumDirection.down),
    LessonEvent(beat: 1, chord: 'Xyz9', direction: StrumDirection.down),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a chord with no known diagram shape names the gap instead of '
      'disappearing silently', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(child: ChordDiagram(label: 'Xyz9')),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Xyz9'), findsNothing); // no fake shape is drawn
    expect(find.byIcon(Icons.music_off), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Xyz9')),
      findsOneWidget,
      reason: 'the missing chord must be NAMED, not silent',
    );
  });

  testWidgets(
    'a lesson built on an unrecognised chord still plays and scores — the '
    'resource gap never blocks practice',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: preferenceOverrides(),
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LearnScreen(lesson: _lessonWithUnknownChord()),
          ),
        ),
      );
      await tester.pump();

      // The screen renders without an exception, names the missing diagram…
      expect(find.byIcon(Icons.music_off), findsOneWidget);
      // …and the transport still works: play/pause is unaffected.
      expect(find.text('Play'), findsOneWidget);
      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(find.text('Pause'), findsOneWidget);
    },
  );
}
