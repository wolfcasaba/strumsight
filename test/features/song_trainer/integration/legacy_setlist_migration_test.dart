import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_setlist_adapter.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_song_reader.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/setlist_repository.dart';

void main() {
  test(
    'persistent legacy mapping preserves order, duplicates and unresolved items after restart',
    () async {
      final repository = _MemorySetlistRepository();
      final legacy = LegacySongReader().readSetlist(<String, dynamic>{
        'id': 'legacy-set',
        'name': 'Legacy',
        'songs': <String>['song-a', 'missing', 'song-a'],
      });
      final songbook = <String, SongDocument>{};

      final migration = await const LegacySetlistAdapter().persistV2(
        legacy,
        songbook,
        repository: repository,
        migratedAt: DateTime.utc(2026, 8, 4),
      );
      final reopened = await repository.get('legacy-set');

      expect(migration.isSuccess, isTrue);
      expect(
        reopened.valueOrNull!.items.map((item) => item.songId.value),
        <String>['song-a', 'missing', 'song-a'],
      );
      expect(reopened.valueOrNull!.items[1].unresolved, isTrue);
    },
  );
}

final class _MemorySetlistRepository implements SetlistRepository {
  final Map<String, SongSetlist> _values = <String, SongSetlist>{};

  @override
  Future<AppResult<void>> delete(String id) async {
    _values.remove(id);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<SongSetlist?>> get(String id) async =>
      Success<SongSetlist?>(_values[id]);

  @override
  Future<AppResult<List<SongSetlist>>> list() async =>
      Success<List<SongSetlist>>(_values.values.toList());

  @override
  Future<AppResult<void>> save(SongSetlist setlist) async {
    _values[setlist.id] = setlist;
    return const Success<void>(null);
  }
}
