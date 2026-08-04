import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/local/file_setlist_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('setlist_repository_test_');
  });
  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test(
    'atomic save survives a fresh repository open with duplicate items intact',
    () async {
      final root = Directory('${sandbox.path}/setlists');
      final repository = await FileSetlistRepository.openAtDirectory(
        directory: root,
      );
      final setlist = SongSetlist(
        id: 'practice-list',
        name: 'Practice list',
        createdAt: DateTime.utc(2026, 8, 4),
        updatedAt: DateTime.utc(2026, 8, 4),
        items: <SongSetlistItem>[
          SongSetlistItem(id: 'first', songId: SongId('song-a')),
          SongSetlistItem(id: 'second', songId: SongId('song-a')),
        ],
      );

      final saved = await repository.save(setlist);
      final reopened = await FileSetlistRepository.openAtDirectory(
        directory: root,
      );
      final loaded = await reopened.get('practice-list');

      expect(saved.isSuccess, isTrue);
      expect(loaded.isSuccess, isTrue);
      expect(loaded.valueOrNull!.items.map((item) => item.id), <String>[
        'first',
        'second',
      ]);
      expect(
        loaded.valueOrNull!.items.map((item) => item.songId.value),
        <String>['song-a', 'song-a'],
      );
    },
  );
}
