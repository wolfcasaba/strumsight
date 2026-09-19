// An in-memory [SongProgressRepository] for compositions that build the real
// Song Trainer controller.
//
// Javító sáv R8 (2026-09-19 integráció): the routed controller now also wires
// a `SongMeasureProgressCommitter`, so it resolves
// `songProgressRepositoryProvider` — the seam `main.dart` overrides with the
// file-backed store. A widget/e2e composition that builds the Stage has to
// override it too, exactly as it already overrides the song and asset
// repositories; otherwise the provider's deliberate bootstrap guard throws
// while the Stage is building.
library;

import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_practice_record.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_progress_repository.dart';

final class InMemorySongProgressRepository implements SongProgressRepository {
  /// Every record handed to [save], in call order.
  final List<SongPracticeRecord> saved = <SongPracticeRecord>[];

  @override
  Future<AppResult<List<SongPracticeRecord>>> load({
    SongId? songId,
    int? revision,
  }) async {
    return Success<List<SongPracticeRecord>>(<SongPracticeRecord>[
      for (final record in saved)
        if ((songId == null || record.songId == songId) &&
            (revision == null || record.songRevision == revision))
          record,
    ]);
  }

  @override
  Future<AppResult<void>> save(SongPracticeRecord record) async {
    saved.add(record);
    return const Success<void>(null);
  }
}
