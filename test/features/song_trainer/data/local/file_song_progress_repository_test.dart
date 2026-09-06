// A fájl-alapú Song-progress tároló nyitási szerződése.
//
// BLOCKER-1 (2026-09-06 review) — MÉRT hiba: `openAtDirectory` mohón
// dekódolt, és a `FormatException` kiszökött. Ez a hívás a szállított úton
// a `runApp` ELŐTT fut (`main.dart` → `composeProductionOverridesOrFailure`
// → `songProgressRepositoryBootProvider`), tehát EGY sérült helyi fájl
// örökre fekete képernyőt jelentett, minden visszaút nélkül.
//
// A helyes viselkedés a `lib/core/storage/json_document_store.dart`
// precedense: a nem dekódolható bájtokat KARANTÉNBA tesszük (semmit nem
// törlünk, a felhasználó adata visszanyerhető marad), és üresen indulunk.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/local/file_song_progress_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_practice_record.dart';

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('song_progress_repo_test_');
  });
  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  Directory root() =>
      Directory('${sandbox.path}/song_progress')..createSync(recursive: true);

  List<File> quarantineFiles(Directory directory) => directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.contains('song_progress.json.corrupt-'))
      .toList();

  test('ép tároló: a mentett rekord az újranyitás után is megvan', () async {
    final directory = root();
    final repository = await FileSongProgressRepository.openAtDirectory(
      directory: directory,
    );

    final saved = await repository.save(_record());
    final reopened = await FileSongProgressRepository.openAtDirectory(
      directory: directory,
    );
    final loaded = await reopened.load();

    expect(saved.isSuccess, isTrue);
    expect(loaded.valueOrNull, hasLength(1));
    expect(loaded.valueOrNull!.single.id, 'record-1');
    expect(quarantineFiles(directory), isEmpty);
  });

  group('sérült tároló', () {
    test('nem dob, üresen indul, és a bájtokat karanténba teszi', () async {
      final directory = root();
      File('${directory.path}/song_progress.json').writeAsStringSync('{ nem');

      final repository = await FileSongProgressRepository.openAtDirectory(
        directory: directory,
        clock: () => DateTime.utc(2026, 9, 6, 12, 30, 15),
      );
      final loaded = await repository.load();

      expect(loaded.isSuccess, isTrue);
      expect(loaded.valueOrNull, isEmpty);

      final quarantined = quarantineFiles(directory);
      expect(quarantined, hasLength(1));
      expect(quarantined.single.readAsStringSync(), '{ nem');
      expect(
        File('${directory.path}/song_progress.json').existsSync(),
        isFalse,
      );
    });

    test('az ISMERETLEN sémaverzió is karanténba kerül', () async {
      final directory = root();
      File(
        '${directory.path}/song_progress.json',
      ).writeAsStringSync('{"schemaVersion": 9999, "items": []}');

      final repository = await FileSongProgressRepository.openAtDirectory(
        directory: directory,
      );

      expect((await repository.load()).valueOrNull, isEmpty);
      expect(quarantineFiles(directory), hasLength(1));
    });

    test('a karantén UTÁN a mentés és az újranyitás működik', () async {
      final directory = root();
      File('${directory.path}/song_progress.json').writeAsStringSync('nem');

      final repository = await FileSongProgressRepository.openAtDirectory(
        directory: directory,
      );
      final saved = await repository.save(_record());
      final reopened = await FileSongProgressRepository.openAtDirectory(
        directory: directory,
      );

      expect(saved.isSuccess, isTrue);
      expect((await reopened.load()).valueOrNull, hasLength(1));
    });
  });
}

SongPracticeRecord _record() => SongPracticeRecord(
  id: 'record-1',
  songId: SongId('song-a'),
  songRevision: 1,
  source: const SongProgressSource(
    measureId: 'm-1',
    eventId: 'e-1',
    measureIndex: 0,
  ),
  activeDuration: const Duration(seconds: 30),
  completed: true,
  score: 0.75,
  recordedAt: DateTime.utc(2026, 9, 6),
);
