import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:strumsight/features/settings/public.dart';

import 'redaction_report.dart';
import 'tutor_context_snapshot.dart';

/// Lab-only structured inspection data. It deliberately has no prompt field.
@immutable
final class InspectableContextView {
  // The Lab view defensively copies the snapshot's collections.
  // ignore: prefer_const_constructors_in_immutables
  InspectableContextView._({
    required this.requestId,
    required this.fields,
    required this.redactionReport,
    required this.estimatedSizeBytes,
    required this.truncatedFields,
  });

  final String requestId;
  final List<TutorContextField> fields;
  final RedactionReport redactionReport;
  final int estimatedSizeBytes;
  final List<TutorContextFieldKey> truncatedFields;

  /// Produces inspection data only when the public Lab preference is enabled.
  static InspectableContextView? forRef({
    required TutorContextSnapshot snapshot,
    required Ref ref,
  }) => forLab(snapshot: snapshot, labModeEnabled: ref.read(labModeProvider));

  /// Pure companion for tests and callers that already read the Lab gate.
  static InspectableContextView? forLab({
    required TutorContextSnapshot snapshot,
    required bool labModeEnabled,
  }) {
    if (!labModeEnabled) return null;
    return InspectableContextView._(
      requestId: snapshot.requestId,
      fields: List<TutorContextField>.unmodifiable(snapshot.fields),
      redactionReport: snapshot.redactionReport,
      estimatedSizeBytes: snapshot.estimatedSizeBytes,
      truncatedFields: List<TutorContextFieldKey>.unmodifiable(
        snapshot.truncatedFields,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'fields': <Object?>[for (final field in fields) field.toJson()],
    'redactionReport': redactionReport.toJson(),
    'estimatedSizeBytes': estimatedSizeBytes,
    'truncatedFields': <Object?>[
      for (final field in truncatedFields) field.name,
    ],
  };
}
