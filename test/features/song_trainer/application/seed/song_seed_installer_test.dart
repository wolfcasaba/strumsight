// E16-R01/A1 — the shipped practice songs land exactly once per device.
//
// The cells that matter are the ones a "restore the defaults on boot"
// implementation gets wrong:
//   1. a fresh device receives the whole catalogue;
//   2. a second launch installs nothing (the marker, not the repository, is
//      the guard);
//   3. a song the user DELETED does not come back on the next launch, but the
//      explicit restore CTA does bring it back.
//
// Plus the failure path: an asset that cannot be read is reported and stays
// out of the marker, so the next launch retries it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/seed/song_seed_installer.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/data/local/song_document_codec.dart';
import 'package:strumsight/features/song_trainer/data/seed/song_seed_marker_store.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';

const _catalog = <SongSeedDefinition>[
  SongSeedDefinition(seedId: 'first', assetKey: 'assets/songs/first.json'),
  SongSeedDefinition(seedId: 'second', assetKey: 'assets/songs/second.json'),
];

void main() {
  late Directory root;
  late InMemorySongRepository repository;
  late SongSeedMarkerStore markerStore;

  setUp(() {
    root = Directory.systemTemp.createTempSync('song_seed_');
    repository = InMemorySongRepository(clock: () => DateTime.utc(2026, 9, 17));
    markerStore = SongSeedMarkerStore.open(songsRoot: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  SongSeedInstaller installer({Map<String, String>? assets}) {
    final bundle = assets ?? _defaultAssets();
    return SongSeedInstaller(
      repository: repository,
      markerStore: markerStore,
      assetLoader: (key) async {
        final value = bundle[key];
        if (value == null) throw StateError('missing asset');
        return value;
      },
      clock: () => DateTime.utc(2026, 9, 17),
      catalog: _catalog,
    );
  }

  Future<List<String>> storedIds() async {
    final listed = await repository.list(const SongQuery());
    return listed.valueOrNull!
        .map((summary) => summary.documentId.value)
        .toList()
      ..sort();
  }

  test('a fresh device receives the whole catalogue', () async {
    final outcome = await installer().install();

    expect(outcome.isClean, isTrue);
    expect(outcome.installedSeedIds, <String>['first', 'second']);
    expect(outcome.skippedSeedIds, isEmpty);
    expect(await storedIds(), <String>['first', 'second']);
    expect(songSeedStateFileFor(root).existsSync(), isTrue);
  });

  test('a second launch installs nothing', () async {
    await installer().install();

    final second = await installer().install();

    expect(second.installedSeedIds, isEmpty);
    expect(second.skippedSeedIds, <String>['first', 'second']);
    expect(await storedIds(), <String>['first', 'second']);
  });

  test(
    'a seed the user deleted does not come back on the next launch',
    () async {
      await installer().install();
      await repository.permanentlyDelete(SongId('first'));
      expect(await storedIds(), <String>['second']);

      await installer().install();

      expect(await storedIds(), <String>['second']);
    },
  );

  test('the explicit restore brings a deleted seed back', () async {
    await installer().install();
    await repository.permanentlyDelete(SongId('first'));

    final restored = await installer().restore();

    expect(restored.isClean, isTrue);
    expect(restored.installedSeedIds, contains('first'));
    expect(await storedIds(), <String>['first', 'second']);
  });

  test('an unreadable asset is named and retried on the next launch', () async {
    final partial = _defaultAssets()..remove('assets/songs/second.json');

    final first = await installer(assets: partial).install();

    expect(first.installedSeedIds, <String>['first']);
    expect(first.failures, <SongSeedFailure>[
      const SongSeedFailure(
        seedId: 'second',
        reason: SongSeedFailureReason.assetUnavailable,
      ),
    ]);
    expect(await storedIds(), <String>['first']);

    final second = await installer().install();

    expect(second.installedSeedIds, <String>['second']);
    expect(await storedIds(), <String>['first', 'second']);
  });

  test('a corrupt marker re-installs the catalogue', () async {
    songSeedStateFileFor(root).writeAsStringSync('not json at all');

    final outcome = await installer().install();

    expect(outcome.installedSeedIds, <String>['first', 'second']);
  });

  test('the shipped catalogue names three declared assets', () {
    expect(songSeedCatalog.map((entry) => entry.seedId).toList(), <String>[
      'seed-harom-akkord-g-c-d',
      'seed-blues-shuffle-a',
      'seed-keringo-g',
    ]);
    for (final entry in songSeedCatalog) {
      expect(File(entry.assetKey).existsSync(), isTrue, reason: entry.assetKey);
    }
  });
}

Map<String, String> _defaultAssets() => <String, String>{
  'assets/songs/first.json': _encode('first', 'First seed'),
  'assets/songs/second.json': _encode('second', 'Second seed'),
};

String _encode(String id, String title) {
  final document = SongDocument(
    schemaVersion: 1,
    id: SongId(id),
    revision: 0,
    metadata: SongMetadata(title: title),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: '$id.song.json',
      sha256: 'a' * 64,
      importedAt: DateTime.utc(2026, 9, 17),
      importerVersion: 'test@1',
    ),
    createdAt: DateTime.utc(2026, 9, 17),
    updatedAt: DateTime.utc(2026, 9, 17),
  );
  return utf8.decode(const SongDocumentCodec().encode(document));
}
