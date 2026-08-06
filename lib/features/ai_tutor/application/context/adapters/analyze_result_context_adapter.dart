import 'package:strumsight/features/analyze/public.dart';

import '../tutor_context_snapshot.dart';

/// Projects a completed Analyze result into a versioned session reference.
final class AnalyzeResultContextAdapter {
  const AnalyzeResultContextAdapter({this.schemaVersion, this.scorerVersion});

  final String? schemaVersion;
  final String? scorerVersion;

  TutorContextField? adapt({
    required String resultId,
    required AnalyzeResult result,
  }) {
    if (!_hasVersion || resultId.trim().isEmpty) return null;
    final chordLabels = <Object?>[];
    for (final chord in result.chords) {
      if (!chordLabels.contains(chord.label)) chordLabels.add(chord.label);
    }
    return TutorContextField.available(
      key: TutorContextFieldKey.analyze,
      values: <String, Object?>{
        'resultId': resultId,
        'durationSeconds': result.durationSec,
        'bpm': result.bpm,
        'beatsPerBar': result.beatsPerBar,
        'strumCount': result.strums.length,
        'downStrumCount': result.downCount,
        'upStrumCount': result.upCount,
        'mlDiagnosticsAvailable': result.diagnostics != null,
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
