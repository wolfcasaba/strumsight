import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/songs/model/setlist.dart';
import 'package:music_theory/features/songs/model/song.dart';
import 'package:music_theory/features/songs/providers/songs_provider.dart';
import 'package:music_theory/features/songs/screens/song_list_screen.dart';
import 'package:music_theory/features/songs/theory/strum_patterns.dart';
import 'package:music_theory/features/songs/widgets/strum_pattern_editor.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 116 — 3/4 songs in the Song Builder. The app has TAUGHT waltz time
/// since r110/111 (curriculum, count-in, bar grid), but users could not
/// AUTHOR it: the Song model was hard-wired to an 8-slot 4/4 bar.
const _d = StrumDirection.down;
const _u = StrumDirection.up;
const StrumDirection? _x = null;

Song _waltzSong({int bpm = 60}) => Song(
      id: 'w1',
      name: 'My Waltz',
      chords: const ['C', 'G'],
      pattern: const [_d, _x, _u, _x, _u, _x], // 6 slots = one 3/4 bar
      beatsPerBar: 3,
      bpm: bpm,
    );

class _SeededSongs extends SongsController {
  _SeededSongs(this._seed);
  final List<Song> _seed;
  @override
  List<Song> build() {
    super.build(); // opens the r150 write gate (mock prefs are empty)
    return _seed;
  }
}

Future<void> pumpSongList(WidgetTester tester, List<Song> seed) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [songsProvider.overrideWith(() => _SeededSongs(seed))],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SongListScreen(),
    ),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Song model in 3/4', () {
    test('toLesson carries the metre — bar 2 starts at beat 3, not 4', () {
      final lesson = _waltzSong().toLesson();
      expect(lesson.beatsPerBar, 3);
      expect(lesson.totalBeats, 6);
      final barTwo = lesson.events.firstWhere((e) => e.chord == 'G');
      expect(barTwo.beat, 3.0);
    });

    test('fromJson fits a corrupt pattern to the metre (release-safe, R1)', () {
      // A hand-edited/corrupt record: 8 slots but bpb=3. The debug assert in
      // _expand is stripped in release, so fromJson must repair it rather than
      // let slots spill into the next bar (round 130).
      final corrupt = {
        'id': 'x',
        'name': 'Corrupt',
        'chords': ['C'],
        'pat': 'dudududu', // 8 slots
        'bpm': 90,
        'bpb': 3, // wants 6
      };
      final song = Song.fromJson(corrupt);
      expect(song.pattern.length, 6, reason: 'truncated to one 3/4 bar');
      // Too-short is padded with rests, never left short.
      final short = Song.fromJson({...corrupt, 'pat': 'd', 'bpb': 4});
      expect(short.pattern.length, 8);
      // toLesson must not throw (the invariant _expand asserts now holds).
      expect(song.toLesson().beatsPerBar, 3);
    });

    test('JSON round-trips the metre; legacy records default to 4/4', () {
      final song = _waltzSong();
      expect(Song.fromJson(song.toJson()), song);
      expect(Song.fromJson(song.toJson()).beatsPerBar, 3);

      final legacy = Song(
        id: 'l1',
        name: 'Old song',
        chords: const ['C'],
        pattern: const [_d, _x, _d, _x, _d, _x, _d, _x],
        bpm: 90,
      ).toJson()
        ..remove('bpb');
      expect(Song.fromJson(legacy).beatsPerBar, 4);
    });

    test('toAnalyzeResult times bars by the metre (share pipeline)', () {
      final r = _waltzSong(bpm: 60).toAnalyzeResult(); // 1 beat = 1 s
      expect(r.durationSec, 6.0, reason: '2 bars × 3 beats × 1 s');
      expect(r.chords[1].startSec, 3.0);
      expect(r.chords[1].endSec, 6.0);
    });

    test('a setlist opening with a 3/4 song counts in as a waltz', () {
      const set = Setlist(id: 's1', name: 'Gig', songIds: ['w1']);
      final lesson = set.combine([_waltzSong()]);
      expect(lesson.beatsPerBar, 3,
          reason: 'count-in/bar grid must follow the opening song');
    });
  });

  group('presets per metre', () {
    test('waltz presets are 6-slot, common presets stay 8-slot', () {
      expect(StrumPatternPreset.forMeter(3), isNotEmpty);
      for (final p in StrumPatternPreset.forMeter(3)) {
        expect(p.pattern.length, 6, reason: '${p.name} must fill a 3/4 bar');
        expect(p.pattern.any((d) => d != null), isTrue);
      }
      expect(StrumPatternPreset.forMeter(4), StrumPatternPreset.all);
      for (final p in StrumPatternPreset.all) {
        expect(p.pattern.length, 8, reason: '${p.name} must fill a 4/4 bar');
      }
    });
  });

  group('song list shows the metre', () {
    testWidgets('a 3/4 song row carries a 3/4 badge, a 4/4 row does not',
        (tester) async {
      // Imports deferred to keep this file model-focused: the list screen
      // and provider come from the flow-test's seeding pattern.
      await pumpSongList(tester, [
        _waltzSong(),
        Song(
          id: 'c1',
          name: 'Common Time',
          chords: const ['C'],
          pattern: const [_d, _x, _d, _x, _d, _x, _d, _x],
          bpm: 90,
        ),
      ]);
      expect(find.textContaining('3/4'), findsOneWidget,
          reason: 'only the waltz row shows the metre');
    });
  });

  group('pattern editor follows the metre', () {
    testWidgets('a 6-slot pattern shows beat labels 1 & 2 & 3 & only',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StrumPatternEditor(
            pattern: const [_d, _x, _u, _x, _u, _x],
            onChanged: (_) {},
          ),
        ),
      ));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsNothing,
          reason: 'a 3/4 bar has no fourth beat');
      expect(find.text('&'), findsNWidgets(3));
    });

    testWidgets('each slot is a screen-reader button announcing beat + state '
        '(round 125 a11y)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StrumPatternEditor(
            pattern: const [_d, _x, _u, _x, _u, _x],
            onChanged: (_) {},
          ),
        ),
      ));

      // Downbeat 1 = down-strum; the off-beat after 1 = a rest; beat 2 = up.
      expect(find.bySemanticsLabel('Beat 1, Down. Tap to change.'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Beat 1 and, Rest. Tap to change.'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Beat 2, Up. Tap to change.'),
          findsOneWidget);
      // The raw "&" glyph must NOT leak into the a11y tree (excludeSemantics).
      expect(find.bySemanticsLabel('&'), findsNothing);

      // …and the slot must be ACTIVATABLE by a screen reader — the label is
      // useless if double-tap dispatches no tap action (round 130 regression:
      // excludeSemantics dropped the child InkWell's action).
      final node =
          tester.getSemantics(find.bySemanticsLabel('Beat 1, Down. Tap to change.'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
          reason: 'a screen-reader activation must reach the toggle');
      handle.dispose();
    });
  });
}
