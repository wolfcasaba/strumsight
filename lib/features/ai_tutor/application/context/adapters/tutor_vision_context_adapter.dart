import 'package:strumsight/features/vision/domain/integration/public.dart';

import '../tutor_context_snapshot.dart';

/// Projects the minimal Vision contract through the redacted Tutor context.
final class TutorVisionContextAdapter {
  const TutorVisionContextAdapter({this.schemaVersion, this.scorerVersion});

  final String? schemaVersion;
  final String? scorerVersion;

  TutorContextField? adapt(VisionContextSnapshot snapshot) {
    if (!_hasVersion) return null;
    return TutorContextField.available(
      key: TutorContextFieldKey.vision,
      values: snapshot.toJson(),
      provenance: ContextProvenance(
        sourceFeature: ContextSourceFeature.vision,
        schemaVersion: schemaVersion,
        scorerVersion: scorerVersion,
      ),
    );
  }

  bool get _hasVersion => schemaVersion != null || scorerVersion != null;
}
