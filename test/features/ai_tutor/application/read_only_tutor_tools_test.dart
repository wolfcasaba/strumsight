import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/redaction_report.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/ai_tutor/application/tools/fake_tutor_tool_registry.dart';
import 'package:strumsight/features/ai_tutor/application/tools/read_only_tutor_tools.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_registry.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_request.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_result.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 5, 12);

  TutorContextSnapshot snapshotWith(Map<String, Object?> values) =>
      TutorContextSnapshot(
        requestId: 'request-42',
        createdAt: createdAt,
        purpose: ContextPurpose.generalQuestion,
        fields: <TutorContextField>[
          TutorContextField.available(
            key: TutorContextFieldKey.studentProfile,
            values: values,
            provenance: ContextProvenance(
              sourceFeature: ContextSourceFeature.aiTutor,
              schemaVersion: 'profile.v1',
            ),
          ),
        ],
        redactionReport: RedactionReport.empty(),
      );

  TutorToolRequest requestFor({
    required String toolName,
    required Map<String, Object?> input,
  }) => TutorToolRequest(
    toolName: toolName,
    input: TutorToolInput(input),
    policy: TutorToolTurnPolicy(
      allowedToolNames: ReadOnlyTutorTools.safeToolNames,
      allowedPermissions: <TutorToolPermission>{
        TutorToolPermission.readLocal,
        TutorToolPermission.computeLocal,
      },
    ),
    timeout: const Duration(seconds: 1),
  );

  test(
    'returns redacted context output with provenance and a timestamp',
    () async {
      final registry = ReadOnlyTutorTools.registryFor(
        snapshot: snapshotWith(<String, Object?>{
          'displayName': 'Nora',
          'apiKey': 'do-not-leak',
          'nested': <String, Object?>{
            'accessToken': 'also-secret',
            'level': 'beginner',
          },
        }),
        clock: () => createdAt,
      );

      final result = await registry.execute(
        requestFor(
          toolName: ReadOnlyTutorTools.getContextFieldName,
          input: const <String, Object?>{'field': 'studentProfile'},
        ),
      );

      final output = result.valueOrNull!;
      expect(output.provenance.source, 'tutor.context_snapshot');
      expect(output.timestamp, createdAt);
      expect(output.payload.values.toString(), isNot(contains('do-not-leak')));
      expect(output.payload.values.toString(), isNot(contains('also-secret')));
      expect(output.payload.values.toString(), contains('Nora'));
    },
  );

  test('explicitly rejects invalid read-only tool input', () async {
    final registry = ReadOnlyTutorTools.registryFor(
      snapshot: snapshotWith(const <String, Object?>{'displayName': 'Nora'}),
      clock: () => createdAt,
    );

    final result = await registry.execute(
      requestFor(
        toolName: ReadOnlyTutorTools.getContextFieldName,
        input: const <String, Object?>{'field': 42},
      ),
    );

    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(result.failureOrNull!.code, FailureCode.validationInvalidInput);
  });

  test('security allowlist rejects a disposable network tool', () {
    final safeTools = ReadOnlyTutorTools.toolsFor(
      snapshotWith(const <String, Object?>{'displayName': 'Nora'}),
    );

    expect(safeTools.map((tool) => tool.name), <String>[
      ReadOnlyTutorTools.getContextFieldName,
      ReadOnlyTutorTools.summarizeContextName,
    ]);
    expect(
      safeTools.map((tool) => tool.permission).toSet(),
      <TutorToolPermission>{
        TutorToolPermission.readLocal,
        TutorToolPermission.computeLocal,
      },
    );
    expect(
      () => TutorToolRegistry(
        version: 'security-test.v1',
        tools: <TutorTool>[...safeTools, const _DisposableNetworkTool()],
        approvedToolNames: ReadOnlyTutorTools.safeToolNames,
        maxOutputBytes: 128,
      ),
      throwsArgumentError,
    );
  });

  test(
    'fake registry records orchestration requests and returns its canned result',
    () async {
      final expected = TutorToolResult.completed(
        payload: TutorToolPayload(<String, Object?>{'safe': true}),
        provenance: const TutorToolProvenance(
          source: 'fake.registry',
          schemaVersion: 'fake.v1',
        ),
        timestamp: createdAt,
        maxOutputBytes: 128,
      );
      final fake = FakeTutorToolRegistry(
        version: 'fake.v1',
        onExecute: (_) async => expected,
      );
      final request = requestFor(
        toolName: ReadOnlyTutorTools.summarizeContextName,
        input: const <String, Object?>{},
      );

      final result = await fake.execute(request);

      expect(result.valueOrNull, expected);
      expect(fake.requests, <TutorToolRequest>[request]);
      expect(fake, isA<TutorToolRegistry>());
    },
  );
}

final class _DisposableNetworkTool implements TutorTool {
  const _DisposableNetworkTool();

  @override
  String get name => 'networkTool';

  @override
  TutorToolPermission get permission => TutorToolPermission.readLocal;

  @override
  TutorToolProvenance get provenance =>
      const TutorToolProvenance(source: 'network', schemaVersion: 'network.v1');

  @override
  TutorToolSchema get inputSchema => TutorToolSchema(
    toolName: 'networkTool',
    fields: <TutorToolSchemaField>[],
  );

  @override
  Future<TutorToolPayload> execute(TutorToolInput input) async =>
      TutorToolPayload(<String, Object?>{});
}
