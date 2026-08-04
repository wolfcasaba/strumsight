import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/library/song_library_controller.dart';
import 'package:strumsight/features/song_trainer/application/library/song_query.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';

void main() {
  test(
    'loads index summaries once and filters locally without document reads',
    () async {
      final repository = _SummaryRepository(<SongSummary>[
        _summary('legacy-song', 'Migrated song', SongSourceType.legacyLocal),
        _summary('v2-song', 'Fresh song', SongSourceType.midi),
      ]);
      final controller = SongLibraryController(repository);
      addTearDown(controller.dispose);

      await controller.load();
      controller.setQuery(const SongLibraryQuery(searchText: 'fresh'));

      expect(controller.state.summaries.map((item) => item.title), <String>[
        'Fresh song',
      ]);
      expect(repository.listCalls, 1);
      expect(repository.getCalls, 0);
    },
  );

  test('trash hides a summary and undo restores it', () async {
    final summary = _summary('song-one', 'Song one', SongSourceType.midi);
    final repository = _SummaryRepository(<SongSummary>[summary]);
    final controller = SongLibraryController(repository);
    addTearDown(controller.dispose);
    await controller.load();

    await controller.moveToTrash(summary.documentId);
    expect(controller.state.summaries, isEmpty);
    expect(controller.state.undoSongId, summary.documentId);

    await controller.undoTrash();
    expect(controller.state.summaries, <SongSummary>[summary]);
    expect(controller.state.undoSongId, isNull);
  });

  test(
    'favorite filter uses stable summary IDs without document reads',
    () async {
      final summary = _summary('song-one', 'Song one', SongSourceType.midi);
      final controller = SongLibraryController(
        _SummaryRepository(<SongSummary>[summary]),
      );
      addTearDown(controller.dispose);
      await controller.load();

      controller.toggleFavorite(summary.documentId);
      controller.setQuery(const SongLibraryQuery(favoritesOnly: true));

      expect(controller.state.summaries, <SongSummary>[summary]);
    },
  );
}

SongSummary _summary(String id, String title, SongSourceType sourceType) =>
    SongSummary(
      documentId: SongId(id),
      title: title,
      artist: null,
      tags: const <String>[],
      updatedAt: DateTime.utc(2026, 8, 4),
      lastPracticedAt: DateTime.utc(2026, 8, 4),
      capability: null,
      sourceType: sourceType,
      favorite: false,
      archived: false,
      revision: 0,
      documentHash: '0' * 64,
      trashed: false,
    );

final class _SummaryRepository implements SongRepository {
  _SummaryRepository(this.summaries);

  final List<SongSummary> summaries;
  int listCalls = 0;
  int getCalls = 0;
  final Set<SongId> _trashed = <SongId>{};

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) async {
    listCalls++;
    return AppResult<List<SongSummary>>.success(
      summaries
          .where(
            (item) =>
                query.includeTrashed || !_trashed.contains(item.documentId),
          )
          .toList(),
    );
  }

  @override
  Future<AppResult<void>> moveToTrash(SongId id) async {
    _trashed.add(id);
    return AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> restore(SongId id) async {
    _trashed.remove(id);
    return AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> create(_) => throw UnimplementedError();
  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      throw UnimplementedError();
  @override
  Future<AppResult<SongDocument?>> get(SongId id) async {
    getCalls++;
    return AppResult<SongDocument?>.success(null);
  }

  @override
  Future<AppResult<void>> update(_, {required int expectedRevision}) =>
      throw UnimplementedError();
}
