import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/inspectable_context_view.dart';
import 'package:strumsight/features/ai_tutor/application/context/redaction_report.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';

void main() {
  final snapshot = TutorContextSnapshot(
    requestId: 'inspect-request',
    createdAt: DateTime.utc(2026, 8, 5),
    purpose: ContextPurpose.generalQuestion,
    fields: <TutorContextField>[
      TutorContextField.available(
        key: TutorContextFieldKey.settings,
        values: <String, Object?>{'capoFret': 2},
        provenance: ContextProvenance(
          sourceFeature: ContextSourceFeature.settings,
          schemaVersion: 'settings.v1',
        ),
      ),
    ],
    redactionReport: RedactionReport(<ContextOmission>[
      const ContextOmission(
        path: 'settings.accessToken',
        reason: ContextOmissionReason.credential,
      ),
    ]),
  );

  test('is unavailable outside Lab mode', () {
    expect(
      InspectableContextView.forLab(snapshot: snapshot, labModeEnabled: false),
      isNull,
    );
  });

  test('exposes structured fields and redaction audit without a prompt', () {
    final view = InspectableContextView.forLab(
      snapshot: snapshot,
      labModeEnabled: true,
    )!;

    expect(view.fields.single.key, TutorContextFieldKey.settings);
    expect(view.redactionReport.entries.single.path, 'settings.accessToken');
    expect(view.toJson().containsKey('prompt'), isFalse);
    expect(view.toJson().toString(), isNot(contains('system prompt')));
  });
}
