import 'package:strumsight/features/progress/public.dart';

import '../tutor_context_snapshot.dart';

/// Projects stable progress rollups instead of individual persisted entries.
final class ProgressContextAdapter {
  const ProgressContextAdapter({this.schemaVersion});

  final String? schemaVersion;

  TutorContextField? adapt(PracticeStats stats) {
    if (schemaVersion == null) return null;
    return TutorContextField.available(
      key: TutorContextFieldKey.progress,
      values: <String, Object?>{
        'totalSessions': stats.totalSessions,
        'totalSeconds': stats.totalSeconds,
        'totalStrokes': stats.totalStrokes,
        'daysPracticed': stats.daysPracticed,
        if (stats.averageDirectionAccuracy != null)
          'averageDirectionAccuracy': stats.averageDirectionAccuracy,
        if (stats.bestDirectionAccuracy != null)
          'bestDirectionAccuracy': stats.bestDirectionAccuracy,
      },
      provenance: ContextProvenance(
        sourceFeature: ContextSourceFeature.progress,
        schemaVersion: schemaVersion,
      ),
    );
  }
}
