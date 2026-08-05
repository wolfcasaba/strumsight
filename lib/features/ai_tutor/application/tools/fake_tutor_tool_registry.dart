import 'dart:async';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_registry.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_request.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_result.dart';

/// In-memory [TutorToolRegistry] double for tutor orchestration tests.
final class FakeTutorToolRegistry extends TutorToolRegistry {
  FakeTutorToolRegistry({
    required super.version,
    required this.onExecute,
    Iterable<TutorToolSchema> schemas = const <TutorToolSchema>[],
  }) : _schemas = List<TutorToolSchema>.unmodifiable(schemas),
       super(
         tools: const <TutorTool>[],
         approvedToolNames: const <String>{},
         maxOutputBytes: 0,
       );

  final FutureOr<TutorToolResult> Function(TutorToolRequest request) onExecute;
  final List<TutorToolSchema> _schemas;
  final List<TutorToolRequest> _requests = <TutorToolRequest>[];

  List<TutorToolRequest> get requests =>
      List<TutorToolRequest>.unmodifiable(_requests);

  @override
  List<TutorToolSchema> schemasForTurn(TutorToolTurnPolicy policy) =>
      List<TutorToolSchema>.unmodifiable(<TutorToolSchema>[
        for (final schema in _schemas)
          if (policy.allowedToolNames.contains(schema.toolName)) schema,
      ]);

  @override
  Future<AppResult<TutorToolResult>> execute(TutorToolRequest request) async {
    _requests.add(request);
    try {
      return AppResult<TutorToolResult>.success(await onExecute(request));
    } on TutorToolInputException {
      return const AppResult<TutorToolResult>.failure(ValidationFailure());
    } catch (_) {
      return const AppResult<TutorToolResult>.failure(UnknownFailure());
    }
  }
}
