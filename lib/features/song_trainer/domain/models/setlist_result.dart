import 'package:meta/meta.dart';

import 'song_setlist.dart';

enum SetlistItemResultStatus { completed, skipped, failed }

/// The outcome of one ordered item in a Setlist session.
@immutable
final class SetlistItemResult {
  const SetlistItemResult._({
    required this.itemId,
    required this.status,
    required this.availability,
    required this.activeDuration,
    required this.repairRequired,
  });

  factory SetlistItemResult.completed({
    required String itemId,
    Duration activeDuration = Duration.zero,
  }) => SetlistItemResult._(
    itemId: itemId,
    status: SetlistItemResultStatus.completed,
    availability: SetlistItemAvailability.ready,
    activeDuration: activeDuration,
    repairRequired: false,
  );

  factory SetlistItemResult.skipped({
    required String itemId,
    required SetlistItemAvailability availability,
  }) => SetlistItemResult._(
    itemId: itemId,
    status: SetlistItemResultStatus.skipped,
    availability: availability,
    activeDuration: Duration.zero,
    repairRequired: true,
  );

  final String itemId;
  final SetlistItemResultStatus status;
  final SetlistItemAvailability availability;
  final Duration activeDuration;
  final bool repairRequired;
}

/// Ordered result of a Setlist Practice or Performance run.
@immutable
final class SetlistResult {
  SetlistResult({
    required this.setlistId,
    required this.mode,
    required List<SetlistItemResult> itemResults,
  }) : itemResults = List<SetlistItemResult>.unmodifiable(itemResults);

  final String setlistId;
  final SetlistSessionMode mode;
  final List<SetlistItemResult> itemResults;

  bool get usesScoring => mode == SetlistSessionMode.practice;
  bool get requiresMicrophone => usesScoring;
  Duration get totalActiveDuration => itemResults.fold<Duration>(
    Duration.zero,
    (total, result) => total + result.activeDuration,
  );
}
