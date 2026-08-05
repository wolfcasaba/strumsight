import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_registry.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_request.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_result.dart';

void main() {
  const provenance = TutorToolProvenance(
    source: 'test.local',
    schemaVersion: 'test.v1',
  );
  final now = DateTime.utc(2026, 8, 5, 12);

  TutorToolRegistry registryFor(
    Iterable<TutorTool> tools, {
    required Set<String> approvedToolNames,
    int maxOutputBytes = 128,
  }) => TutorToolRegistry(
    version: 'registry.v1',
    tools: tools,
    approvedToolNames: approvedToolNames,
    maxOutputBytes: maxOutputBytes,
    clock: () => now,
  );

  TutorToolRequest requestFor({
    required String toolName,
    Map<String, Object?> input = const <String, Object?>{},
    Set<String>? allowedToolNames,
    Set<TutorToolPermission>? allowedPermissions,
    Duration timeout = const Duration(seconds: 1),
  }) => TutorToolRequest(
    toolName: toolName,
    input: TutorToolInput(input),
    policy: TutorToolTurnPolicy(
      allowedToolNames: allowedToolNames ?? <String>{toolName},
      allowedPermissions:
          allowedPermissions ??
          <TutorToolPermission>{TutorToolPermission.readLocal},
    ),
    timeout: timeout,
  );

  test('exposes its version and only schemas allowed for the turn', () {
    final readTool = _TestTool(
      name: 'readLocal',
      permission: TutorToolPermission.readLocal,
      provenance: provenance,
      onExecute: (_) async => TutorToolPayload(<String, Object?>{}),
    );
    final computeTool = _TestTool(
      name: 'computeLocal',
      permission: TutorToolPermission.computeLocal,
      provenance: provenance,
      onExecute: (_) async => TutorToolPayload(<String, Object?>{}),
    );
    final registry = registryFor(
      <TutorTool>[readTool, computeTool],
      approvedToolNames: <String>{'readLocal', 'computeLocal'},
    );

    final schemas = registry.schemasForTurn(
      TutorToolTurnPolicy(
        allowedToolNames: <String>{'readLocal'},
        allowedPermissions: <TutorToolPermission>{
          TutorToolPermission.readLocal,
        },
      ),
    );

    expect(registry.version, 'registry.v1');
    expect(schemas.map((schema) => schema.toolName), <String>['readLocal']);
  });

  test('fails closed for an unknown tool', () async {
    final registry = registryFor(
      const <TutorTool>[],
      approvedToolNames: const <String>{},
    );

    final result = await registry.execute(requestFor(toolName: 'unknownTool'));

    expect(result, isA<Failure<TutorToolResult>>());
    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(result.failureOrNull!.code, FailureCode.validationInvalidInput);
  });

  test('rejects a registered tool omitted from the turn allowlist', () async {
    final tool = _TestTool(
      name: 'readLocal',
      permission: TutorToolPermission.readLocal,
      provenance: provenance,
      onExecute: (_) async => TutorToolPayload(<String, Object?>{}),
    );
    final registry = registryFor(
      <TutorTool>[tool],
      approvedToolNames: <String>{'readLocal'},
    );

    final result = await registry.execute(
      requestFor(toolName: 'readLocal', allowedToolNames: const <String>{}),
    );

    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(result.failureOrNull!.code, FailureCode.validationInvalidInput);
  });

  test(
    'rejects a turn permission mismatch without executing the tool',
    () async {
      var invoked = false;
      final tool = _TestTool(
        name: 'computeLocal',
        permission: TutorToolPermission.computeLocal,
        provenance: provenance,
        onExecute: (_) async {
          invoked = true;
          return TutorToolPayload(<String, Object?>{});
        },
      );
      final registry = registryFor(
        <TutorTool>[tool],
        approvedToolNames: <String>{'computeLocal'},
      );

      final result = await registry.execute(
        requestFor(
          toolName: 'computeLocal',
          allowedPermissions: const <TutorToolPermission>{
            TutorToolPermission.readLocal,
          },
        ),
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(invoked, isFalse);
    },
  );

  test(
    'normalizes invalid tool input to the existing validation failure',
    () async {
      final tool = _TestTool(
        name: 'readLocal',
        permission: TutorToolPermission.readLocal,
        provenance: provenance,
        onExecute: (_) async => throw const TutorToolInputException(),
      );
      final registry = registryFor(
        <TutorTool>[tool],
        approvedToolNames: <String>{'readLocal'},
      );

      final result = await registry.execute(requestFor(toolName: 'readLocal'));

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(result.failureOrNull!.code, FailureCode.validationInvalidInput);
    },
  );

  test(
    'normalizes an unexpected tool exception to the existing unknown failure',
    () async {
      final tool = _TestTool(
        name: 'readLocal',
        permission: TutorToolPermission.readLocal,
        provenance: provenance,
        onExecute: (_) async => throw StateError('unexpected'),
      );
      final registry = registryFor(
        <TutorTool>[tool],
        approvedToolNames: <String>{'readLocal'},
      );

      final result = await registry.execute(requestFor(toolName: 'readLocal'));

      expect(result.failureOrNull, isA<UnknownFailure>());
      expect(result.failureOrNull!.code, FailureCode.unknown);
    },
  );

  test('reports a timeout as a typed result with provenance', () async {
    final tool = _TestTool(
      name: 'readLocal',
      permission: TutorToolPermission.readLocal,
      provenance: provenance,
      onExecute: (_) => Future<TutorToolPayload>.delayed(
        const Duration(milliseconds: 30),
        () => TutorToolPayload(<String, Object?>{}),
      ),
    );
    final registry = registryFor(
      <TutorTool>[tool],
      approvedToolNames: <String>{'readLocal'},
    );

    final result = await registry.execute(
      requestFor(
        toolName: 'readLocal',
        timeout: const Duration(milliseconds: 1),
      ),
    );

    final timedOut = result.valueOrNull!;
    expect(timedOut.state, TutorToolExecutionState.timedOut);
    expect(timedOut.provenance, provenance);
    expect(timedOut.timestamp, now);
  });

  test(
    'reports output size below, at, and above its limit without truncation',
    () async {
      Future<TutorToolResult> executePayload(
        Map<String, Object?> payload, {
        required int limit,
      }) async {
        final tool = _TestTool(
          name: 'readLocal',
          permission: TutorToolPermission.readLocal,
          provenance: provenance,
          onExecute: (_) async => TutorToolPayload(payload),
        );
        final registry = registryFor(
          <TutorTool>[tool],
          approvedToolNames: <String>{'readLocal'},
          maxOutputBytes: limit,
        );
        return (await registry.execute(
          requestFor(toolName: 'readLocal'),
        )).valueOrNull!;
      }

      const payload = <String, Object?>{'report': 'abcdefgh'};
      final bytes = utf8.encode(jsonEncode(payload)).length;

      final below = await executePayload(payload, limit: bytes + 1);
      final at = await executePayload(payload, limit: bytes);
      final above = await executePayload(payload, limit: bytes - 1);

      expect(below.sizeReport.isOversized, isFalse);
      expect(at.sizeReport.isOversized, isFalse);
      expect(above.sizeReport.isOversized, isTrue);
      expect(above.sizeReport.excessBytes, 1);
      expect(above.payload.values, payload);
    },
  );
}

final class _TestTool implements TutorTool {
  const _TestTool({
    required this.name,
    required this.permission,
    required this.provenance,
    required this.onExecute,
  });

  @override
  final String name;

  @override
  final TutorToolPermission permission;

  @override
  final TutorToolProvenance provenance;

  final Future<TutorToolPayload> Function(TutorToolInput input) onExecute;

  @override
  TutorToolSchema get inputSchema =>
      TutorToolSchema(toolName: name, fields: const <TutorToolSchemaField>[]);

  @override
  Future<TutorToolPayload> execute(TutorToolInput input) => onExecute(input);
}
