import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/screens/learn_screen.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/songs/model/setlist.dart';
import 'package:music_theory/features/songs/model/song.dart';
import 'package:music_theory/features/songs/providers/setlists_provider.dart';
import 'package:music_theory/features/songs/providers/songs_provider.dart';
import 'package:music_theory/features/songs/screens/setlist_detail_screen.dart';
import 'package:music_theory/features/songs/screens/setlist_list_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SeededSongs extends SongsController {
  _SeededSongs(this._seed);
  final List<Song> _seed;
  @override
  List<Song> build() {
    super.build(); // opens the r150 write gate (mock prefs are empty)
    return _seed;
  }
}

class _SeededSetlists extends SetlistsController {
  _SeededSetlists(this._seed);
  final List<Setlist> _seed;
  @override
  List<Setlist> build() {
    super.build(); // opens the r150 write gate (mock prefs are empty)
    return _seed;
  }
}

const _song = Song(
  id: 'a',
  name: 'First Song',
  chords: ['C', 'G'],
  pattern: [StrumDirection.down, null, StrumDirection.down, null, //
    StrumDirection.down, null, StrumDirection.down, null],
  bpm: 100,
);

Widget _app(Widget home,
        {List<Song> songs = const [], List<Setlist> setlists = const []}) =>
    ProviderScope(
      overrides: [
        songsProvider.overrideWith(() => _SeededSongs(songs)),
        setlistsProvider.overrideWith(() => _SeededSetlists(setlists)),
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

  testWidgets('empty setlists shows the group-your-songs nudge', (tester) async {
    await tester.pumpWidget(_app(const SetlistListScreen()));
    await tester.pump();
    expect(find.textContaining('Group your songs'), findsOneWidget);
  });

  testWidgets('detail shows songs, Play set enabled, remove works',
      (tester) async {
    const set = Setlist(id: 's', name: 'My Gig', songIds: ['a']);
    await tester.pumpWidget(_app(
      const SetlistDetailScreen(setlistId: 's'),
      songs: [_song],
      setlists: [set],
    ));
    await tester.pump();

    expect(find.text('First Song'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Play set'), findsOneWidget);

    // Remove the only song → the empty-detail hint replaces the list.
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();
    expect(find.text('First Song'), findsNothing);
    expect(find.textContaining('Add songs to this set'), findsOneWidget);
  });

  testWidgets('Play set launches the combined lesson', (tester) async {
    const set = Setlist(id: 's', name: 'My Gig', songIds: ['a']);
    await tester.pumpWidget(_app(
      const SetlistDetailScreen(setlistId: 's'),
      songs: [_song],
      setlists: [set],
    ));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Play set'));
    await tester.pumpAndSettle();
    expect(find.byType(LearnScreen), findsOneWidget);
  });
}
