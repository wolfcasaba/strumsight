import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_budget.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/redaction_report.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';

void main() {
  TutorContextSnapshot snapshot() => TutorContextSnapshot(
    requestId: 'budget-request',
    createdAt: DateTime.utc(2026, 8, 5),
    purpose: ContextPurpose.generalQuestion,
    redactionReport: RedactionReport.empty(),
    fields: <TutorContextField>[
      TutorContextField.available(
        key: TutorContextFieldKey.studentProfile,
        values: <String, Object?>{'locale': 'hu'},
        provenance: ContextProvenance(
          sourceFeature: ContextSourceFeature.aiTutor,
          schemaVersion: 'profile.v1',
        ),
      ),
      TutorContextField.available(
        key: TutorContextFieldKey.settings,
        values: <String, Object?>{'tuningReferenceHz': 440},
        provenance: ContextProvenance(
          sourceFeature: ContextSourceFeature.settings,
          schemaVersion: 'settings.v1',
        ),
      ),
    ],
  );

  test(
    'uses an inclusive exact budget and truncates the lowest-priority field deterministically',
    () {
      final unbudgeted = snapshot();
      final exactLimit = unbudgeted.estimatedSizeBytes;

      // Independently calculated from canonical UTF-8 JSON with `python3 -c`.
      expect(exactLimit, 462);

      final below = ContextBudget(
        maxSerializedBytes: exactLimit + 1,
      ).apply(unbudgeted);
      final equal = ContextBudget(
        maxSerializedBytes: exactLimit,
      ).apply(unbudgeted);
      final above = ContextBudget(
        maxSerializedBytes: exactLimit - 1,
      ).apply(unbudgeted);
      final repeatedAbove = ContextBudget(
        maxSerializedBytes: exactLimit - 1,
      ).apply(snapshot());

      expect(below.truncatedFields, isEmpty);
      expect(equal.truncatedFields, isEmpty);
      expect(above.truncatedFields, <TutorContextFieldKey>[
        TutorContextFieldKey.settings,
      ]);
      expect(above.estimatedSizeBytes, lessThanOrEqualTo(exactLimit - 1));
      expect(above.canonicalJson, repeatedAbove.canonicalJson);
      expect(
        above.redactionReport.entries.last.reason,
        ContextOmissionReason.contextBudget,
      );
    },
  );
}
