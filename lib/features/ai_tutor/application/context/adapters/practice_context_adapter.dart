import 'package:strumsight/features/practice/public.dart';

import '../tutor_context_snapshot.dart';

/// Projects aggregate, raw-audio-free values from the Practice public contract.
final class PracticeContextAdapter {
  const PracticeContextAdapter({this.schemaVersion, this.scorerVersion});

  final String? schemaVersion;
  final String? scorerVersion;

  TutorContextField? adapt(PracticeSessionResult result) {
    if (!_hasVersion) return null;
    return TutorContextField.available(
      key: TutorContextFieldKey.practice,
      values: <String, Object?>{
        'sessionId': result.id,
        'activeSeconds': result.activeDuration.inSeconds,
        'pausedSeconds': result.pausedDuration.inSeconds,
        'attemptCount': result.attempts.length,
        'finishReason': result.finishReason.code,
        if (result.highestStableTempo != null)
          'highestStableTempoBpm': result.highestStableTempo!.bpm,
        if (result.coachingSummary.isNotEmpty)
          'coachingCodes': List<Object?>.from(result.coachingSummary),
      },
      provenance: ContextProvenance(
        sourceFeature: ContextSourceFeature.practice,
        schemaVersion: schemaVersion,
        scorerVersion: scorerVersion,
      ),
    );
  }

  bool get _hasVersion => schemaVersion != null || scorerVersion != null;
}
