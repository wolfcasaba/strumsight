import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/learn/audio/chord_audio.dart';
import 'package:music_theory/features/learn/audio/metronome.dart';
import 'package:music_theory/features/learn/widgets/lesson_highway.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/share/screens/strum_reel_screen.dart';
import 'package:music_theory/features/share/share_service.dart';
import 'package:music_theory/l10n/app_localizations.dart';

class _FakeShareService extends ShareService {
  const _FakeShareService(this.log);
  final List<String> log;

  @override
  Future<void> shareText(AnalyzeResult result,
          {int capo = 0, Rect? sharePositionOrigin}) async =>
      log.add('text-share capo=$capo strums=${result.strums.length}');
}

class _FakeMetronome extends Metronome {
  final List<String> log = [];

  @override
  Future<void> tick({bool accent = false}) async =>
      log.add(accent ? 'accent' : 'click');
}

class _FakeBacking extends Backing {
  final List<String> log = [];

  @override
  Future<void> playChord(String label) async => log.add(label);
}

final _result = AnalyzeResult(
  durationSec: 4,
  bpm: 100,
  chords: const [
    TimelineChord(label: 'C', startSec: 0, endSec: 2),
    TimelineChord(label: 'G', startSec: 2, endSec: 4),
  ],
  strums: [
    for (var i = 0; i < 6; i++)
      TimelineStrum(
        direction: i.isEven ? StrumDirection.down : StrumDirection.up,
        timeSec: i * 0.5,
        confidence: 1,
      ),
  ],
);

void main() {
  testWidgets('the reel renders branded and animates the recording',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StrumReelScreen(result: _result),
    ));
    await tester.pump();

    // Branded + shows the chords + the animated highway.
    expect(find.text('StrumSight'), findsOneWidget);
    expect(find.text('C · G'), findsOneWidget);
    expect(find.byType(LessonHighway), findsOneWidget);
    expect(find.textContaining('#StrumSightChallenge'), findsOneWidget);

    // It advances (looping ticker); drive time manually, never pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // Tap to pause so no active ticker survives to teardown.
    await tester.tap(find.byType(LessonHighway));
    await tester.pump();
  });

  testWidgets('one-tap share sends the caption from the reel (016b P7)',
      (tester) async {
    final log = <String>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StrumReelScreen(
          result: _result, capo: 2, shareService: _FakeShareService(log)),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump();
    expect(log, ['text-share capo=2 strums=6']);

    await tester.tap(find.byType(LessonHighway)); // pause ticker
    await tester.pump();
  });

  testWidgets('pause/resume continues from where it stopped (no beat-0 jump)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StrumReelScreen(result: _result),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900)); // mid-loop

    await tester.tap(find.byType(LessonHighway)); // pause
    await tester.pump();
    final paused =
        tester.widget<LessonHighway>(find.byType(LessonHighway)).playheadBeat;
    expect(paused, greaterThan(1.0)); // 0.9 s @100 BPM = 1.5 beats

    await tester.tap(find.byType(LessonHighway)); // resume
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final resumed =
        tester.widget<LessonHighway>(find.byType(LessonHighway)).playheadBeat;
    expect(resumed, greaterThanOrEqualTo(paused),
        reason: 'resume must continue, not restart the ticker at beat 0');

    await tester.tap(find.byType(LessonHighway)); // pause for teardown
    await tester.pump();
  });

  testWidgets('the reel SOUNDS: clicks ride the drawn beats, chords the bars',
      (tester) async {
    final metronome = _FakeMetronome();
    final backing = _FakeBacking();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StrumReelScreen(
          result: _result, metronome: metronome, backing: backing),
    ));
    await tester.pump();
    // The opening downbeat sounds immediately: accented click + the C pad —
    // the animation and the audio start from the SAME playhead instant.
    await tester.pump(const Duration(milliseconds: 50));
    expect(metronome.log, ['accent']);
    expect(backing.log, ['C']);

    // 100 BPM → 600 ms/beat: beat 1 is a plain click, no new chord.
    await tester.pump(const Duration(milliseconds: 650));
    expect(metronome.log, ['accent', 'click']);
    expect(backing.log, ['C']);

    await tester.tap(find.byType(LessonHighway)); // pause ticker
    await tester.pump();
  });

  testWidgets('the reel sound toggle mutes clicks and chords', (tester) async {
    final metronome = _FakeMetronome();
    final backing = _FakeBacking();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StrumReelScreen(
          result: _result, metronome: metronome, backing: backing),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.volume_up)); // mute
    await tester.pump();
    final clicksAtMute = metronome.log.length;
    final chordsAtMute = backing.log.length;

    await tester.pump(const Duration(milliseconds: 1300)); // ~2 beats
    expect(metronome.log.length, clicksAtMute,
        reason: 'muted reel must not click');
    expect(backing.log.length, chordsAtMute,
        reason: 'muted reel must not play chords');

    await tester.tap(find.byIcon(Icons.volume_off)); // unmute
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    expect(metronome.log.length, greaterThan(clicksAtMute),
        reason: 'unmuting resumes the clicks');

    await tester.tap(find.byType(LessonHighway)); // pause ticker
    await tester.pump();
  });

  testWidgets('pause silences the reel; the loop wrap re-sounds the downbeat',
      (tester) async {
    final metronome = _FakeMetronome();
    final backing = _FakeBacking();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StrumReelScreen(
          result: _result, metronome: metronome, backing: backing),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byType(LessonHighway)); // pause
    await tester.pump();
    final clicksAtPause = metronome.log.length;
    await tester.pump(const Duration(milliseconds: 1300));
    expect(metronome.log.length, clicksAtPause,
        reason: 'a paused reel is silent');

    await tester.tap(find.byType(LessonHighway)); // resume
    await tester.pump();
    // Drive across the loop wrap (totalBeats 8 @100 BPM = 4.8 s): the wrap
    // is beat 0 again — accent + chord must re-fire, in sync with the
    // highway jumping back.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 450));
    }
    expect(metronome.log.where((e) => e == 'accent').length, greaterThan(1),
        reason: 'the wrap re-sounds the bar-0 downbeat');
    expect(backing.log.length, greaterThan(1));

    await tester.tap(find.byType(LessonHighway)); // pause for teardown
    await tester.pump();
  });

  test('downbeat punch-in kicks on the bar and decays (016b P7)', () {
    final onBeat = StrumReelScreen.punchScale(0);
    final offBeat = StrumReelScreen.punchScale(2.0);
    expect(onBeat, greaterThan(1.03));
    expect(offBeat, closeTo(1.0, 0.005));
    // Kicks again on the next bar.
    expect(StrumReelScreen.punchScale(4.0), closeTo(onBeat, 1e-9));
  });

  test('the end-card fades in over the loop tail only', () {
    expect(StrumReelScreen.endCardOpacity(0, 16), 0);
    expect(StrumReelScreen.endCardOpacity(10, 16), 0);
    expect(StrumReelScreen.endCardOpacity(14.5, 16), 0);
    expect(StrumReelScreen.endCardOpacity(15.25, 16), closeTo(1.0, 1e-9));
    // Short clips skip the end-card (nothing to brand over).
    expect(StrumReelScreen.endCardOpacity(2.9, 3), 0);
  });

  testWidgets('the end-card appears near the loop end', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StrumReelScreen(result: _result),
    ));
    await tester.pump();
    // Hidden at the start: the wordmark appears only once (the header).
    expect(find.text('StrumSight'), findsOneWidget);

    // _result: 6 strums @0.5 s, 100 BPM → the lesson loops over its bars;
    // drive close to the loop end: totalBeats of the derived lesson is 8
    // (2 bars), loop period = 8 beats @100 BPM = 4.8 s → 4.5 s is in the tail.
    await tester.pump(const Duration(milliseconds: 4500));
    expect(find.text('StrumSight'), findsNWidgets(2),
        reason: 'the branded end-card is visible in the loop tail');

    await tester.tap(find.byType(LessonHighway)); // pause ticker
    await tester.pump();
  });
}
