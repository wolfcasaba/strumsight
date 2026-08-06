import 'package:strumsight/features/practice/public.dart';

import '../tutor_context_snapshot.dart';

/// Projects a completed Practice result into a versioned session reference.
final class PracticeResultContextAdapter {
  const PracticeResultContextAdapter({this.schemaVersion, this.scorerVersion});

  final String? schemaVersion;
  final String? scorerVersion;

  TutorContextField? adapt(PracticeSessionResult result) {
    if (!_hasVersion || result.id.trim().isEmpty) return null;
    return TutorContextField.available(
      key: TutorContextFieldKey.practice,
      values: <String, Object?>{
        'resultId': result.id,
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
