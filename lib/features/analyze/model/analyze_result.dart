import 'package:flutter/foundation.dart';

import '../../live/model/strum.dart';

/// A chord that sounded over a span of the clip.
@immutable
class TimelineChord {
  const TimelineChord({
    required this.label,
    required this.startSec,
    required this.endSec,
  });

  final String label;
  final double startSec;
  final double endSec;

  double get durationSec => endSec - startSec;

  Map<String, dynamic> toJson() =>
      {'label': label, 'start': startSec, 'end': endSec};

  factory TimelineChord.fromJson(Map<String, dynamic> j) => TimelineChord(
        label: j['label'] as String,
        startSec: (j['start'] as num).toDouble(),
        endSec: (j['end'] as num).toDouble(),
      );
}

/// A single strum detected at a point in the clip.
@immutable
class TimelineStrum {
  const TimelineStrum({
    required this.direction,
    required this.timeSec,
    required this.confidence,
  });

  final StrumDirection direction;
  final double timeSec;
  final double confidence;

  bool get isDown => direction == StrumDirection.down;

  Map<String, dynamic> toJson() => {
        'dir': direction.name,
        'time': timeSec,
        'conf': confidence,
      };

  factory TimelineStrum.fromJson(Map<String, dynamic> j) => TimelineStrum(
        direction: StrumDirection.values.byName(j['dir'] as String),
        timeSec: (j['time'] as num).toDouble(),
        confidence: (j['conf'] as num).toDouble(),
      );
}

/// The result of analysing a recorded clip: the chord timeline, the strum
/// marks, and summary stats.
@immutable
class AnalyzeResult {
  const AnalyzeResult({
    required this.durationSec,
    required this.bpm,
    required this.chords,
    required this.strums,
    this.beatsPerBar = 4,
  });

  final double durationSec;
  final double bpm;
  final List<TimelineChord> chords;
  final List<TimelineStrum> strums;

  /// The clip's metre. Recorded clips can't detect one and stay 4/4; a
  /// synthetic result from a user SONG carries the song's own (round 118 —
  /// a shared waltz's reel looped in 4/4).
  final int beatsPerBar;

  int get downCount => strums.where((s) => s.isDown).length;
  int get upCount => strums.length - downCount;

  /// A compact one-line summary of the chords, e.g. "C · G · Am · F".
  String get chordSummary {
    final labels = <String>[];
    for (final c in chords) {
      if (labels.isEmpty || labels.last != c.label) labels.add(c.label);
    }
    return labels.join(' · ');
  }

  static const empty =
      AnalyzeResult(durationSec: 0, bpm: 0, chords: [], strums: []);

  Map<String, dynamic> toJson() => {
        'duration': durationSec,
        'bpm': bpm,
        'chords': chords.map((c) => c.toJson()).toList(),
        'strums': strums.map((s) => s.toJson()).toList(),
        'bpb': beatsPerBar,
      };

  factory AnalyzeResult.fromJson(Map<String, dynamic> j) => AnalyzeResult(
        durationSec: (j['duration'] as num).toDouble(),
        bpm: (j['bpm'] as num).toDouble(),
        chords: (j['chords'] as List)
            .map((e) => TimelineChord.fromJson(e as Map<String, dynamic>))
            .toList(),
        strums: (j['strums'] as List)
            .map((e) => TimelineStrum.fromJson(e as Map<String, dynamic>))
            .toList(),
        // Records saved before round 118 are all 4/4.
        beatsPerBar: (j['bpb'] as num?)?.toInt() ?? 4,
      );
}
