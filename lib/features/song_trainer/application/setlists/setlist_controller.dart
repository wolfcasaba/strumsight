import 'package:strumsight/core/foundation/app_result.dart';

import '../../domain/models/song_setlist.dart';
import '../../domain/repositories/setlist_repository.dart';

/// Small application facade for Setlist V2 list/editor operations.
final class SetlistController {
  const SetlistController(this._repository);

  final SetlistRepository _repository;

  Future<AppResult<List<SongSetlist>>> load() => _repository.list();
  Future<AppResult<void>> save(SongSetlist setlist) =>
      _repository.save(setlist);
  Future<AppResult<void>> remove(String id) => _repository.delete(id);
}
