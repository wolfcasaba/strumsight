import 'context_budget.dart';
import 'context_purpose.dart';
import 'redaction_report.dart';
import 'tutor_context_snapshot.dart';

/// Produces the purpose-minimized, deterministic tutor context snapshot.
final class TutorContextAssembler {
  const TutorContextAssembler({this.budget});

  final ContextBudget? budget;

  TutorContextSnapshot assemble({
    required String requestId,
    required DateTime createdAt,
    required ContextPurpose purpose,
    required Iterable<TutorContextField> fields,
  }) {
    final ordered = fields.toList()
      ..sort((left, right) => left.key.index.compareTo(right.key.index));
    final keys = <TutorContextFieldKey>{};
    final included = <TutorContextField>[];
    final omissions = <ContextOmission>[];
    const redactor = ContextRedactor();

    for (final field in ordered) {
      if (!keys.add(field.key)) {
        throw ArgumentError.value(
          fields,
          'fields',
          'Duplicate context field key.',
        );
      }
      if (!purpose.allowedFields.contains(field.key)) {
        omissions.add(
          ContextOmission(
            path: field.key.name,
            reason: ContextOmissionReason.purposeNotAllowed,
          ),
        );
        continue;
      }
      if (field.availability == ContextFieldAvailability.available &&
          !field.provenance.hasVersion) {
        omissions.add(
          ContextOmission(
            path: field.key.name,
            reason: ContextOmissionReason.missingVersion,
          ),
        );
        continue;
      }
      final redacted = redactor.redact(field);
      included.add(redacted.field);
      omissions.addAll(redacted.report.entries);
    }

    final snapshot = TutorContextSnapshot(
      requestId: requestId,
      createdAt: createdAt,
      purpose: purpose,
      fields: included,
      redactionReport: RedactionReport(omissions),
    );
    return budget?.apply(snapshot) ?? snapshot;
  }
}
