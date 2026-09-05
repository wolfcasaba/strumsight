import 'package:meta/meta.dart';

import 'song_setlist.dart';

/// Egy dalcsomag-tétel kimenetele.
///
/// A `partial` 2026-09-05-én került be (felhasználói döntés): ha a tanuló
/// félbehagy egy dalt, az addigi eredménye SZÁMÍT — az értékelés azt mutatja,
/// ameddig eljutott. Enélkül két rossz lehetőség maradt volna: `completed`-nek
/// jelölni (hamis állítás, mintha végigjátszotta volna) vagy `failed`-nek
/// (szintén hamis — nem bukott el, csak abbahagyta).
enum SetlistItemResultStatus { completed, partial, skipped, failed }

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

  /// Félbehagyott tétel: a tanuló elhagyta a dalt, mielőtt a végére ért.
  ///
  /// A [activeDuration] a TÉNYLEGESEN eljátszott idő — ebből látszik, meddig
  /// jutott. A `repairRequired` hamis: nincs mit megjavítani, a tétel maga
  /// rendben volt.
  factory SetlistItemResult.partial({
    required String itemId,
    required Duration activeDuration,
  }) => SetlistItemResult._(
    itemId: itemId,
    status: SetlistItemResultStatus.partial,
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
