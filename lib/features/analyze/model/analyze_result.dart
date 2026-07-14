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

/// Lab-mode diagnostics attached to an [AnalyzeResult] (ship-path step 4,
/// r197): the ML chord-model timeline decoded ALONGSIDE the DSP one, plus how
/// often they agree. Null on every default (Lab-mode-off) result — attaching it
/// never changes the flag-off shape or behaviour.
@immutable
class MlChordDiagnostics {
  const MlChordDiagnostics({
    required this.mlChords,
    required this.agreement,
  });

  /// The full-band CRNN chord timeline (majmin labels), time-aligned in seconds
  /// to the same clip as [AnalyzeResult.chords] (its own CQT frame grid).
  final List<TimelineChord> mlChords;

  /// Fraction (0..1) of ML-hop frames where the ML and DSP chord timelines
  /// agree, both reduced to majmin. Diagnostic only.
  final double agreement;

  Map<String, dynamic> toJson() => {
        'mlChords': mlChords.map((c) => c.toJson()).toList(),
        'agreement': agreement,
      };

  factory MlChordDiagnostics.fromJson(Map<String, dynamic> j) =>
      MlChordDiagnostics(
        mlChords: (j['mlChords'] as List)
            .map((e) => TimelineChord.fromJson(e as Map<String, dynamic>))
            .toList(),
        agreement: (j['agreement'] as num).toDouble(),
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
    this.diagnostics,
  });

  final double durationSec;
  final double bpm;
  final List<TimelineChord> chords;
  final List<TimelineStrum> strums;

  /// The clip's metre. Recorded clips can't detect one and stay 4/4; a
  /// synthetic result from a user SONG carries the song's own (round 118 —
  /// a shared waltz's reel looped in 4/4).
  final int beatsPerBar;

  /// Optional Lab-mode ML-vs-DSP diagnostics (r197). Null unless
  /// `labModeProvider` is ON — the default (flag-off) result carries none, so
  /// no existing behaviour, shape, or serialization changes.
  final MlChordDiagnostics? diagnostics;

  /// Return a copy with [diagnostics] attached (Lab mode). Everything else is
  /// carried verbatim — the DSP timeline is untouched.
  AnalyzeResult withDiagnostics(MlChordDiagnostics d) => AnalyzeResult(
        durationSec: durationSec,
        bpm: bpm,
        chords: chords,
        strums: strums,
        beatsPerBar: beatsPerBar,
        diagnostics: d,
      );

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
        // Only present in Lab mode — a flag-off result serializes identically
        // to before r197 (the 'diag' key is simply absent).
        if (diagnostics != null) 'diag': diagnostics!.toJson(),
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
        diagnostics: j['diag'] == null
            ? null
            : MlChordDiagnostics.fromJson(j['diag'] as Map<String, dynamic>),
      );
}
