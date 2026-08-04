import 'package:strumsight/core/foundation/app_result.dart';

import '../models/song_id.dart';
import '../models/song_practice_record.dart';

/// Persistence boundary for versioned Song Trainer progress records.
abstract interface class SongProgressRepository {
  Future<AppResult<List<SongPracticeRecord>>> load({
    SongId? songId,
    int? revision,
  });

  Future<AppResult<void>> save(SongPracticeRecord record);
}
