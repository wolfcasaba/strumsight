import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/learn/screens/learn_screen.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/songs/model/setlist.dart';
import 'package:strumsight/features/songs/model/song.dart';
import 'package:strumsight/features/songs/providers/setlists_provider.dart';
import 'package:strumsight/features/songs/providers/songs_provider.dart';
import 'package:strumsight/features/songs/screens/setlist_detail_screen.dart';
import 'package:strumsight/features/songs/screens/setlist_list_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/preference_store.dart';

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
  pattern: [
    StrumDirection.down, null, StrumDirection.down, null, //
    StrumDirection.down, null, StrumDirection.down, null,
  ],
  bpm: 100,
);

Widget _app(
  Widget home, {
  List<Song> songs = const [],
  List<Setlist> setlists = const [],
  Locale locale = const Locale('en'),
  double textScale = 1,
}) => ProviderScope(
  overrides: [
    ...preferenceOverrides(),
    songsProvider.overrideWith(() => _SeededSongs(songs)),
    setlistsProvider.overrideWith(() => _SeededSetlists(setlists)),
  ],
  child: MaterialApp(
    theme: SsLightTheme.data(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty setlists shows the group-your-songs nudge', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const SetlistListScreen()));
    await tester.pump();
    expect(find.textContaining('Group your songs'), findsOneWidget);
  });

  testWidgets('detail shows songs, Play set enabled, remove works', (
    tester,
  ) async {
    const set = Setlist(id: 's', name: 'My Gig', songIds: ['a']);
    await tester.pumpWidget(
      _app(
        const SetlistDetailScreen(setlistId: 's'),
        songs: [_song],
        setlists: [set],
      ),
    );
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
    await tester.pumpWidget(
      _app(
        const SetlistDetailScreen(setlistId: 's'),
        songs: [_song],
        setlists: [set],
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Play set'));
    await tester.pumpAndSettle();
    expect(find.byType(LearnScreen), findsOneWidget);
  });

  // A2 — the migrated empty states keep the same next action the FAB always
  // offered (§0.0.A/R9 G3: no fabricated affordance, just also reachable
  // from the empty view).
  testWidgets('empty setlists action button opens the same create dialog '
      'as the FAB', (tester) async {
    await tester.pumpWidget(_app(const SetlistListScreen()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ss-empty-state-action')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('empty detail action button opens the same add-song sheet '
      'as the FAB', (tester) async {
    const set = Setlist(id: 's', name: 'My Gig', songIds: []);
    await tester.pumpWidget(
      _app(
        const SetlistDetailScreen(setlistId: 's'),
        songs: [_song],
        setlists: [set],
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ss-empty-state-action')));
    await tester.pumpAndSettle();
    expect(find.text('First Song'), findsOneWidget);
  });

  // A3 — the mandatory 1.5 / 2.0 / 2.5 threshold triple, en AND hu: 2.0 is
  // inclusive-required, 1.5 is below it, 2.5 is above it and not itself a
  // requirement (§6, "küszöb-cellahármas"). Phone-sized viewport (360×640,
  // devicePixelRatio 1.0) is mandatory here: the default `flutter_test`
  // 800×600 canvas is wider than any real phone, which is exactly why the
  // detail screen's own `SsEmptyState` overflow (review 1. forduló BLOCKER-1)
  // stayed invisible to this matrix before.
  for (final scale in [1.5, 2.0, 2.5]) {
    for (final locale in [const Locale('en'), const Locale('hu')]) {
      testWidgets('empty setlists list renders without overflow at textScaler '
          '$scale ($locale)', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(const SetlistListScreen(), locale: locale, textScale: scale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'populated setlists list renders without overflow at textScaler '
        '$scale ($locale)',
        (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          const set = Setlist(id: 's', name: 'My Gig', songIds: ['a']);
          await tester.pumpWidget(
            _app(
              const SetlistListScreen(),
              songs: [_song],
              setlists: [set],
              locale: locale,
              textScale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('empty setlist detail renders without overflow at textScaler '
          '$scale ($locale)', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        const set = Setlist(id: 's', name: 'My Gig', songIds: []);
        await tester.pumpWidget(
          _app(
            const SetlistDetailScreen(setlistId: 's'),
            songs: [_song],
            setlists: [set],
            locale: locale,
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'populated setlist detail renders without overflow at textScaler '
        '$scale ($locale)',
        (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          const set = Setlist(id: 's', name: 'My Gig', songIds: ['a']);
          await tester.pumpWidget(
            _app(
              const SetlistDetailScreen(setlistId: 's'),
              songs: [_song],
              setlists: [set],
              locale: locale,
              textScale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
