import '../../analyze/public.dart' as legacy;
import '../../../core/music/strum.dart' as legacy_core;
import '../public.dart';

/// Projects V2 timeline evidence into the unchanged V1 Analyze UI contract.
final class LegacyViewAdapter {
  const LegacyViewAdapter();

  legacy.AnalyzeResult toAnalyzeResult(AnalysisDocument document) =>
      legacy.AnalyzeResult(
        durationSec: _seconds(document.timeline.duration),
        bpm: document.timeline.tempoPoints.isEmpty
            ? 0
            : document.timeline.tempoPoints.first.bpm,
        chords: <legacy.TimelineChord>[
          for (final chord in document.timeline.chordSegments)
            legacy.TimelineChord(
              label: chord.label,
              startSec: _seconds(chord.start),
              endSec: _seconds(chord.end),
            ),
        ],
        strums: <legacy.TimelineStrum>[
          for (final strum in document.timeline.events.whereType<StrumEvent>())
            legacy.TimelineStrum(
              direction: switch (strum.direction) {
                StrumDirection.down => legacy_core.StrumDirection.down,
                StrumDirection.up => legacy_core.StrumDirection.up,
                StrumDirection.unknown => throw ArgumentError.value(
                  strum.direction,
                  'strum.direction',
                  'cannot render an unknown V2 strum as V1 evidence',
                ),
              },
              timeSec: _seconds(strum.time),
              confidence: strum.confidence,
            ),
        ],
        beatsPerBar: _beatsPerBar(document),
      );

  static double _seconds(Duration value) =>
      value.inMicroseconds / Duration.microsecondsPerSecond;

  static int _beatsPerBar(AnalysisDocument document) {
    for (final warning in document.warnings) {
      if (warning.kind != AnalysisWarningKind.migration) continue;
      final value = int.tryParse(warning.messageArgs['beatsPerBar'] ?? '');
      if (value != null && value >= 1 && value <= 16) return value;
    }
    return 4;
  }
}
