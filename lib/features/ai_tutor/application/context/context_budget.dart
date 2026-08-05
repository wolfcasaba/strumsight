import 'redaction_report.dart';
import 'tutor_context_snapshot.dart';

/// Deterministic UTF-8 serialization budget for a tutor context snapshot.
final class ContextBudget {
  const ContextBudget({required this.maxSerializedBytes})
    : assert(maxSerializedBytes >= 0);

  final int maxSerializedBytes;

  /// Removal order, from least to most useful when context space is scarce.
  static const List<TutorContextFieldKey> truncationPriority =
      <TutorContextFieldKey>[
        TutorContextFieldKey.settings,
        TutorContextFieldKey.streak,
        TutorContextFieldKey.songTrainer,
        TutorContextFieldKey.progress,
        TutorContextFieldKey.analyze,
        TutorContextFieldKey.practice,
        TutorContextFieldKey.skillEvidence,
        TutorContextFieldKey.activeGoals,
        TutorContextFieldKey.guitarProfile,
        TutorContextFieldKey.studentProfile,
      ];

  /// Applies an inclusive limit: a snapshot exactly at the limit is retained.
  TutorContextSnapshot apply(TutorContextSnapshot snapshot) {
    if (snapshot.estimatedSizeBytes <= maxSerializedBytes) return snapshot;

    final retained = snapshot.fields.toList();
    final truncated = <TutorContextFieldKey>[];
    var report = snapshot.redactionReport;
    var result = snapshot;

    for (final key in truncationPriority) {
      final index = retained.indexWhere((field) => field.key == key);
      if (index < 0) continue;

      retained.removeAt(index);
      truncated.add(key);
      report = report.plus(<ContextOmission>[
        ContextOmission(
          path: key.name,
          reason: ContextOmissionReason.contextBudget,
        ),
      ]);
      result = snapshot.withBudgetResult(
        fields: retained,
        redactionReport: report,
        truncatedFields: truncated,
      );
      if (result.estimatedSizeBytes <= maxSerializedBytes) return result;
    }

    return result;
  }
}
