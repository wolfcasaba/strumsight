import 'package:flutter/foundation.dart';

/// Where a practice moment came from. Kept small + stable — the string names are
/// persisted, so never rename an existing value (add new ones at the end).
enum PracticeSource { live, analyze, learn }

/// One recorded practice moment. Days are an integer **epoch day** (local-midnight
/// days since the Unix epoch), matching the streak store, so all history maths is
/// pure integer arithmetic — no timezone/DST drift.
///
/// [directionAccuracy] is the fraction (0..1) of strokes played in the RIGHT
/// **strum direction** (↓/↑) during a scored Learn run — the one metric no
/// competitor tracks. It is `null` for sources that don't score direction
/// (Live, Analyze), so averages only fold real scores.
@immutable
class PracticeEntry {
  const PracticeEntry({
    required this.day,
    required this.source,
    this.seconds = 0,
    this.strokes = 0,
    this.chords = 0,
    this.directionAccuracy,
  });

  /// Epoch day (local midnight) the practice happened on.
  final int day;

  final PracticeSource source;

  /// Best-effort duration of the moment, in seconds (0 when unknown, e.g. a
  /// single Live strum with no measured session length).
  final int seconds;

  /// Strums played / scored in this moment.
  final int strokes;

  /// Distinct chords involved (for Analyze/Learn; 0 when unknown).
  final int chords;

  /// Strum-direction accuracy 0..1 for a scored run, else null. THE moat metric.
  final double? directionAccuracy;

  Map<String, dynamic> toJson() => {
        'day': day,
        'src': source.name,
        'sec': seconds,
        'str': strokes,
        'chd': chords,
        if (directionAccuracy != null) 'dir': directionAccuracy,
      };

  factory PracticeEntry.fromJson(Map<String, dynamic> j) => PracticeEntry(
        day: (j['day'] as num).toInt(),
        // Unknown/renamed source names degrade to `live` rather than throwing on
        // an old persisted blob.
        source: PracticeSource.values.firstWhere(
          (s) => s.name == j['src'],
          orElse: () => PracticeSource.live,
        ),
        seconds: (j['sec'] as num?)?.toInt() ?? 0,
        strokes: (j['str'] as num?)?.toInt() ?? 0,
        chords: (j['chd'] as num?)?.toInt() ?? 0,
        directionAccuracy: (j['dir'] as num?)?.toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is PracticeEntry &&
      other.day == day &&
      other.source == source &&
      other.seconds == seconds &&
      other.strokes == strokes &&
      other.chords == chords &&
      other.directionAccuracy == directionAccuracy;

  @override
  int get hashCode =>
      Object.hash(day, source, seconds, strokes, chords, directionAccuracy);
}
