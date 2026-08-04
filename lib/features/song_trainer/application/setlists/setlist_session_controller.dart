import '../../domain/models/setlist_result.dart';
import '../../domain/models/song_setlist.dart';

typedef SetlistAvailabilityResolver =
    SetlistItemAvailability Function(SongSetlistItem item);
typedef SetlistItemRunner =
    Future<SetlistItemResult> Function(SongSetlistItem item);

/// Coordinates ordered Setlist runs without owning a microphone or gateway.
///
/// Practice delegates scored work to [practiceRunner]. Performance delegates
/// only playback/navigation to [performanceRunner], so it never constructs a
/// scoring runner on this boundary.
final class SetlistSessionController {
  const SetlistSessionController({
    required SetlistAvailabilityResolver availability,
    required SetlistItemRunner practiceRunner,
    required SetlistItemRunner performanceRunner,
  }) : this._(availability, practiceRunner, performanceRunner);

  const SetlistSessionController._(
    this._availability,
    this._practiceRunner,
    this._performanceRunner,
  );

  final SetlistAvailabilityResolver _availability;
  final SetlistItemRunner _practiceRunner;
  final SetlistItemRunner _performanceRunner;

  Future<SetlistResult> run({
    required SongSetlist setlist,
    required SetlistSessionMode mode,
  }) async {
    final results = <SetlistItemResult>[];
    final runner = mode == SetlistSessionMode.practice
        ? _practiceRunner
        : _performanceRunner;
    for (final item in setlist.items) {
      final availability = _availability(item);
      if (availability != SetlistItemAvailability.ready) {
        results.add(
          SetlistItemResult.skipped(
            itemId: item.id,
            availability: availability,
          ),
        );
        continue;
      }
      final result = await runner(item);
      if (result.itemId != item.id) {
        throw StateError('Setlist runner returned a result for another item.');
      }
      results.add(result);
    }
    return SetlistResult(
      setlistId: setlist.id,
      mode: mode,
      itemResults: results,
    );
  }
}
