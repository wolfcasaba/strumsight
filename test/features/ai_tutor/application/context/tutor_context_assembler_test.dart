import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_budget.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/redaction_report.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_assembler.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';

void main() {
  const requestId = 'request-42';
  final createdAt = DateTime.utc(2026, 8, 5, 12);

  TutorContextField availableField({
    required TutorContextFieldKey key,
    required ContextSourceFeature sourceFeature,
    required Map<String, Object?> values,
  }) {
    return TutorContextField.available(
      key: key,
      values: values,
      provenance: ContextProvenance(
        sourceFeature: sourceFeature,
        schemaVersion: 'source.v1',
      ),
    );
  }

  test(
    'keeps only the purpose allowlist in an immutable deterministic snapshot',
    () {
      final profileValues = <String, Object?>{'locale': 'hu'};
      final candidates = <TutorContextField>[
        availableField(
          key: TutorContextFieldKey.studentProfile,
          sourceFeature: ContextSourceFeature.aiTutor,
          values: profileValues,
        ),
        availableField(
          key: TutorContextFieldKey.practice,
          sourceFeature: ContextSourceFeature.practice,
          values: <String, Object?>{'activeSeconds': 120},
        ),
      ];

      final first = const TutorContextAssembler().assemble(
        requestId: requestId,
        createdAt: createdAt,
        purpose: ContextPurpose.profileUpdate,
        fields: candidates,
      );
      final second = const TutorContextAssembler().assemble(
        requestId: requestId,
        createdAt: createdAt,
        purpose: ContextPurpose.profileUpdate,
        fields: candidates,
      );

      expect(first.requestId, requestId);
      expect(
        first.fields.map((field) => field.key),
        equals(<TutorContextFieldKey>[TutorContextFieldKey.studentProfile]),
      );
      expect(first.canonicalJson, second.canonicalJson);
      expect(
        first.redactionReport.entries.single.reason,
        ContextOmissionReason.purposeNotAllowed,
      );

      profileValues['locale'] = 'en';
      expect(first.fields.single.values['locale'], 'hu');
      expect(() => first.fields.add(candidates.first), throwsUnsupportedError);
      expect(
        () => first.fields.single.values['locale'] = 'en',
        throwsUnsupportedError,
      );
    },
  );

  test('enforces the complete purpose by field allowlist matrix', () {
    final allFields = <TutorContextField>[
      for (final key in TutorContextFieldKey.values)
        TutorContextField.available(
          key: key,
          values: const <String, Object?>{},
          provenance: ContextProvenance(
            sourceFeature: ContextSourceFeature.aiTutor,
            schemaVersion: 'matrix.v1',
          ),
        ),
    ];
    const expected = <ContextPurpose, List<TutorContextFieldKey>>{
      ContextPurpose.generalQuestion: <TutorContextFieldKey>[
        TutorContextFieldKey.studentProfile,
        TutorContextFieldKey.guitarProfile,
        TutorContextFieldKey.activeGoals,
        TutorContextFieldKey.skillEvidence,
        TutorContextFieldKey.progress,
        TutorContextFieldKey.settings,
      ],
      ContextPurpose.sessionDebrief: <TutorContextFieldKey>[
        TutorContextFieldKey.studentProfile,
        TutorContextFieldKey.skillEvidence,
        TutorContextFieldKey.practice,
        TutorContextFieldKey.songTrainer,
        TutorContextFieldKey.analyze,
        TutorContextFieldKey.settings,
      ],
      ContextPurpose.progressReview: <TutorContextFieldKey>[
        TutorContextFieldKey.studentProfile,
        TutorContextFieldKey.activeGoals,
        TutorContextFieldKey.skillEvidence,
        TutorContextFieldKey.progress,
        TutorContextFieldKey.streak,
      ],
      ContextPurpose.practicePlanning: <TutorContextFieldKey>[
        TutorContextFieldKey.studentProfile,
        TutorContextFieldKey.guitarProfile,
        TutorContextFieldKey.activeGoals,
        TutorContextFieldKey.skillEvidence,
        TutorContextFieldKey.practice,
        TutorContextFieldKey.progress,
        TutorContextFieldKey.settings,
      ],
      ContextPurpose.songHelp: <TutorContextFieldKey>[
        TutorContextFieldKey.studentProfile,
        TutorContextFieldKey.guitarProfile,
        TutorContextFieldKey.songTrainer,
        TutorContextFieldKey.analyze,
        TutorContextFieldKey.settings,
      ],
      ContextPurpose.profileUpdate: <TutorContextFieldKey>[
        TutorContextFieldKey.studentProfile,
        TutorContextFieldKey.guitarProfile,
        TutorContextFieldKey.activeGoals,
        TutorContextFieldKey.settings,
      ],
    };

    for (final purpose in ContextPurpose.values) {
      final snapshot = const TutorContextAssembler().assemble(
        requestId: '${purpose.name}-request',
        createdAt: createdAt,
        purpose: purpose,
        fields: allFields,
      );
      expect(
        snapshot.fields.map((field) => field.key),
        expected[purpose],
        reason: purpose.name,
      );
    }
  });

  test('applies its optional budget after purpose filtering and redaction', () {
    final snapshot =
        const TutorContextAssembler(
          budget: ContextBudget(maxSerializedBytes: 0),
        ).assemble(
          requestId: requestId,
          createdAt: createdAt,
          purpose: ContextPurpose.profileUpdate,
          fields: <TutorContextField>[
            availableField(
              key: TutorContextFieldKey.studentProfile,
              sourceFeature: ContextSourceFeature.aiTutor,
              values: <String, Object?>{'locale': 'hu'},
            ),
          ],
        );

    expect(snapshot.truncatedFields, <TutorContextFieldKey>[
      TutorContextFieldKey.studentProfile,
    ]);
    expect(snapshot.fields, isEmpty);
  });
}
