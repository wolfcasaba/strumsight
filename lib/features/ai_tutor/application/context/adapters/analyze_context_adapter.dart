import 'package:strumsight/features/analyze/public.dart';

import '../tutor_context_snapshot.dart';

/// Projects summary analysis evidence without timelines, frames, or file paths.
final class AnalyzeContextAdapter {
  const AnalyzeContextAdapter({this.schemaVersion, this.scorerVersion});

  final String? schemaVersion;
  final String? scorerVersion;

  TutorContextField? adapt(AnalyzeResult result) {
    if (!_hasVersion) return null;
    final chordLabels = <Object?>[];
    for (final chord in result.chords) {
      if (!chordLabels.contains(chord.label)) chordLabels.add(chord.label);
    }
    return TutorContextField.available(
      key: TutorContextFieldKey.analyze,
      values: <String, Object?>{
        'durationSeconds': result.durationSec,
        'bpm': result.bpm,
        'beatsPerBar': result.beatsPerBar,
        'strumCount': result.strums.length,
        'downStrumCount': result.downCount,
        'upStrumCount': result.upCount,
        if (chordLabels.isNotEmpty) 'chordLabels': chordLabels,
      },
      provenance: ContextProvenance(
        sourceFeature: ContextSourceFeature.analyze,
        schemaVersion: schemaVersion,
        scorerVersion: scorerVersion,
      ),
    );
  }

  bool get _hasVersion => schemaVersion != null || scorerVersion != null;
}
