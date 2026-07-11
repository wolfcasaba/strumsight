import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/chord_shape.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/share/widgets/strum_card.dart';
import 'package:music_theory/features/songs/model/song.dart';
import 'package:music_theory/features/songs/providers/songs_provider.dart';
import 'package:music_theory/features/songs/screens/song_list_screen.dart';
import 'package:music_theory/features/songs/widgets/strum_pattern_editor.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A songbook seeded with fixed songs, not touching disk.
class _SeededSongs extends SongsController {
  _SeededSongs(this._seed);
  final List<Song> _seed;
  @override
  List<Song> build() => _seed;
}

Widget _app(Widget home, {List<Song>? seed}) => ProviderScope(
      overrides: [
        if (seed != null) songsProvider.overrideWith(() => _SeededSongs(seed)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty songbook shows the build-your-own nudge', (tester) async {
    await tester.pumpWidget(_app(const SongListScreen()));
    await tester.pump();
    expect(find.textContaining('Build your own song'), findsOneWidget);
  });

  testWidgets('create a song end-to-end: name → chord → save → appears',
      (tester) async {
    await tester.pumpWidget(_app(const SongListScreen()));
    await tester.pump();

    // Open the builder.
    await tester.tap(find.text('New song'));
    await tester.pumpAndSettle();

    // Name it.
    await tester.enterText(find.byType(TextField), 'Test Song');
    await tester.pump();

    // Add the first available chord.
    final label = ChordShapes.allLabels.first;
    final chip = find.widgetWithText(ActionChip, label).first;
    await tester.scrollUntilVisible(chip, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(chip);
    await tester.pump();

    // Save → back to the list, where the new song shows.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Test Song'), findsOneWidget);
  });

  testWidgets('the metre toggle switches the builder to a 6-slot 3/4 bar '
      'and the saved song keeps it', (tester) async {
    // Round 116 — author a waltz, not just play the curriculum's.
    await tester.pumpWidget(_app(const SongListScreen()));
    await tester.pump();
    await tester.tap(find.text('New song'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Waltz Draft');
    await tester.pump();
    final label = ChordShapes.allLabels.first;
    final chip = find.widgetWithText(ActionChip, label).first;
    await tester.scrollUntilVisible(chip, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(chip);
    await tester.pump();

    // Switch to 3/4 — the editor drops to 6 slots (no beat "4" label).
    final meter = find.text('3/4');
    await tester.scrollUntilVisible(meter, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(meter);
    await tester.pump();
    expect(find.text('4'), findsNothing,
        reason: 'a 3/4 bar has no fourth beat label');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(SongListScreen)));
    final song = container.read(songsProvider).single;
    expect(song.beatsPerBar, 3);
    expect(song.pattern.length, 6);
    expect(song.pattern.any((d) => d != null), isTrue,
        reason: 'the metre switch must keep the song playable');
  });

  testWidgets('suggest-a-progression fills the chord list', (tester) async {
    await tester.pumpWidget(_app(const SongListScreen()));
    await tester.pump();
    await tester.tap(find.text('New song'));
    await tester.pumpAndSettle();

    // Open the suggestion sheet and pick the Pop progression (default key C).
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();
    expect(find.text('Suggest a progression'), findsOneWidget);
    // Tap the Pop tile via its unique roman-numeral subtitle (a "Pop" strum
    // preset chip also exists in the builder underneath the sheet).
    await tester.tap(find.text('I–V–vi–IV'));
    await tester.pumpAndSettle();

    // Pop in C = C G Am F → each added as a removable InputChip.
    expect(find.widgetWithText(InputChip, 'Am'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'F'), findsOneWidget);
  });

  testWidgets('sharing a song opens the Strum Card preview', (tester) async {
    const song = Song(
      id: 's1',
      name: 'My Song',
      chords: ['C', 'G', 'Am', 'F'],
      pattern: [
        StrumDirection.down, null, StrumDirection.down, StrumDirection.up, //
        null, StrumDirection.up, StrumDirection.down, null,
      ],
      bpm: 100,
    );
    await tester.pumpWidget(_app(const SongListScreen(), seed: [song]));
    await tester.pump();
    expect(find.text('My Song'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();
    // The share pipeline (Strum Card) is reused verbatim for a song.
    expect(find.byType(StrumCard), findsOneWidget);
  });

  testWidgets('a strum-pattern preset fills the editor', (tester) async {
    await tester.pumpWidget(_app(const SongListScreen()));
    await tester.pump();
    await tester.tap(find.text('New song'));
    await tester.pumpAndSettle();

    // The preset row + editor are below the fold — scroll them into view.
    final eighths = find.widgetWithText(ActionChip, 'Eighths');
    await tester.scrollUntilVisible(eighths, 120,
        scrollable: find.byType(Scrollable).first);

    // Default builder pattern is "Down" → no up-strokes yet.
    expect(find.byIcon(Icons.arrow_upward), findsNothing);

    // Apply the "Eighths" preset → 4 up-strokes appear in the editor.
    await tester.tap(eighths);
    await tester.pump();
    expect(find.byIcon(Icons.arrow_upward), findsNWidgets(4));
  });

  testWidgets('pattern editor cycles a rest slot to a down-strum on tap',
      (tester) async {
    List<StrumDirection?>? emitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StrumPatternEditor(
          pattern: List<StrumDirection?>.filled(8, null),
          onChanged: (p) => emitted = p,
        ),
      ),
    ));
    await tester.tap(find.byType(InkWell).first);
    expect(emitted, isNotNull);
    expect(emitted![0], StrumDirection.down); // rest → down
  });
}
