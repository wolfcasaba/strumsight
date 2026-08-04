import 'package:strumsight/core/foundation/app_result.dart';

import '../models/song_setlist.dart';

/// Persistence boundary for ordered, duplicate-preserving Setlist V2 data.
abstract interface class SetlistRepository {
  Future<AppResult<List<SongSetlist>>> list();
  Future<AppResult<SongSetlist?>> get(String id);
  Future<AppResult<void>> save(SongSetlist setlist);
  Future<AppResult<void>> delete(String id);
}
