// E13-R23 — acceptance A5 (setlist order + per-item readiness) and A6 (a
// missing song is named in the setlist, never silently dropped).
//
// §0.0/B/R20 (measured): `SetlistListScreenV2` is not registered on a
// GoRoute and its constructor requires `controller` + `clock` — the widget
// is instantiated directly here with a `SetlistController` backed by a fake
// `SetlistRepository`, per the brief's mandated test shape.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/setlists/setlist_controller.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/setlist_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'setlist order and per-item readiness are rendered correctly (A5)',
    (tester) async {
      final setlist = _mixedSetlist();
      final controller = SetlistController(
        _FakeSetlistRepository(<SongSetlist>[setlist]),
      );

      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      // Order is preserved: item-1 (ready) sits left of item-2
      // (missingAsset), which sits left of item-3 (missingSong).
      final x1 = tester
          .getTopLeft(
            find.byKey(const Key('setlist-readiness-setlist-1-item-1')),
          )
          .dx;
      final x2 = tester
          .getTopLeft(
            find.byKey(const Key('setlist-readiness-setlist-1-item-2')),
          )
          .dx;
      final x3 = tester
          .getTopLeft(
            find.byKey(const Key('setlist-readiness-setlist-1-item-3')),
          )
          .dx;
      expect(x1, lessThan(x2));
      expect(x2, lessThan(x3));

      // Per-item readiness is correct: ready / missingAsset / missingSong.
      // The Card/ListTile merges descendant Semantics into one node, so the
      // per-badge state is verified through the rendered Icon instead of
      // `tester.getSemantics` (which would return the whole tile's label).
      final readyIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('setlist-readiness-setlist-1-item-1')),
          matching: find.byType(Icon),
        ),
      );
      expect(readyIcon.icon, Icons.check_circle_outline);
      expect(readyIcon.color, Colors.green);

      final missingAssetIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('setlist-readiness-setlist-1-item-2')),
          matching: find.byType(Icon),
        ),
      );
      expect(missingAssetIcon.icon, Icons.music_off_outlined);
      expect(missingAssetIcon.color, Colors.orange);

      // No item was dropped: the count still reflects all three.
      expect(find.text('3 songs'), findsOneWidget);
    },
  );

  testWidgets(
    'a missing song is named in the setlist, not silently dropped (A6)',
    (tester) async {
      final setlist = _mixedSetlist();
      final controller = SetlistController(
        _FakeSetlistRepository(<SongSetlist>[setlist]),
      );

      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      final badgeFinder = find.byKey(
        const Key('setlist-readiness-setlist-1-item-3'),
      );
      expect(badgeFinder, findsOneWidget);
      // The unresolved item names the songId as visible text — never a
      // silent omission (A6).
      expect(
        find.descendant(
          of: badgeFinder,
          matching: find.byIcon(Icons.error_outline),
        ),
        findsOneWidget,
      );
      expect(find.text('Song not found: song-gone'), findsOneWidget);
    },
  );
}

Widget _app(SetlistController controller) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: SetlistListScreenV2(
    controller: controller,
    clock: () => DateTime.utc(2026, 8, 1),
  ),
);

SongSetlist _mixedSetlist() {
  final now = DateTime.utc(2026, 8, 1);
  return SongSetlist(
    id: 'setlist-1',
    name: 'Gig Set',
    createdAt: now,
    updatedAt: now,
    items: <SongSetlistItem>[
      SongSetlistItem(id: 'item-1', songId: SongId('song-ready')),
      SongSetlistItem(
        id: 'item-2',
        songId: SongId('song-no-backing'),
        initialAvailability: SetlistItemAvailability.missingAsset,
      ),
      SongSetlistItem(
        id: 'item-3',
        songId: SongId('song-gone'),
        initialAvailability: SetlistItemAvailability.missingSong,
      ),
    ],
  );
}

final class _FakeSetlistRepository implements SetlistRepository {
  _FakeSetlistRepository(this._setlists);

  final List<SongSetlist> _setlists;

  @override
  Future<AppResult<List<SongSetlist>>> list() async =>
      AppResult<List<SongSetlist>>.success(_setlists);

  @override
  Future<AppResult<SongSetlist?>> get(String id) async {
    for (final setlist in _setlists) {
      if (setlist.id == id) return AppResult<SongSetlist?>.success(setlist);
    }
    return AppResult<SongSetlist?>.success(null);
  }

  @override
  Future<AppResult<void>> save(SongSetlist setlist) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> delete(String id) => throw UnimplementedError();
}
