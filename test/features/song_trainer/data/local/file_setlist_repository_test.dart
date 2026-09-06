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

  // -----------------------------------------------------------------
  // BLOCKER-1 (2026-09-06 review) — egy sérült tároló nem állíthatja meg
  // az appot.
  //
  // MÉRT hiba: `openAtDirectory` mohón dekódolt, és a `FormatException`
  // kiszökött. Ez a hívás a szállított úton a `runApp` ELŐTT fut, tehát
  // EGY sérült helyi fájl örökre fekete képernyőt jelentett. A helyes
  // viselkedés a `JsonDocumentStore` precedense: a bájtokat KARANTÉNBA
  // tesszük (semmit nem törlünk), és üresen indulunk.
  // -----------------------------------------------------------------
  group('sérült tároló', () {
    test('nem dob, üresen indul, és a bájtokat karanténba teszi', () async {
      final root = Directory('${sandbox.path}/setlists')
        ..createSync(recursive: true);
      File('${root.path}/setlists.json').writeAsStringSync('{ nem json');

      final repository = await FileSetlistRepository.openAtDirectory(
        directory: root,
        clock: () => DateTime.utc(2026, 9, 6, 12, 30, 15),
      );
      final listed = await repository.list();

      expect(listed.isSuccess, isTrue);
      expect(listed.valueOrNull, isEmpty);

      final quarantined = root
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('setlists.json.corrupt-'))
          .toList();
      expect(quarantined, hasLength(1));
      expect(quarantined.single.readAsStringSync(), '{ nem json');
      // Az eredeti név szabad — a következő mentés tiszta dokumentumot ír.
      expect(File('${root.path}/setlists.json').existsSync(), isFalse);
    });

    test('az ISMERETLEN sémaverzió is karanténba kerül, nem hazudik üreset '
        'csendben', () async {
      final root = Directory('${sandbox.path}/setlists')
        ..createSync(recursive: true);
      File(
        '${root.path}/setlists.json',
      ).writeAsStringSync('{"schemaVersion": 9999, "items": []}');

      final repository = await FileSetlistRepository.openAtDirectory(
        directory: root,
      );

      expect((await repository.list()).valueOrNull, isEmpty);
      expect(
        root.listSync().whereType<File>().any(
          (file) => file.path.contains('setlists.json.corrupt-'),
        ),
        isTrue,
      );
    });

    test('a karantén UTÁN a mentés és az újranyitás működik', () async {
      final root = Directory('${sandbox.path}/setlists')
        ..createSync(recursive: true);
      File('${root.path}/setlists.json').writeAsStringSync('nem json');

      final repository = await FileSetlistRepository.openAtDirectory(
        directory: root,
      );
      final saved = await repository.save(
        SongSetlist(
          id: 'after-corrupt',
          name: 'After corrupt',
          createdAt: DateTime.utc(2026, 9, 6),
          updatedAt: DateTime.utc(2026, 9, 6),
          items: const <SongSetlistItem>[],
        ),
      );
      final reopened = await FileSetlistRepository.openAtDirectory(
        directory: root,
      );

      expect(saved.isSuccess, isTrue);
      expect((await reopened.list()).valueOrNull, hasLength(1));
    });
  });
}
