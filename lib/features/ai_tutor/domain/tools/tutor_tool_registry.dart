import 'dart:collection';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

import 'tutor_tool.dart';
import 'tutor_tool_request.dart';
import 'tutor_tool_result.dart';

/// Registry for an explicitly approved tutor tool set.
class TutorToolRegistry {
  TutorToolRegistry({
    required this.version,
    required Iterable<TutorTool> tools,
    required Iterable<String> approvedToolNames,
    required this.maxOutputBytes,
    DateTime Function()? clock,
  }) : _approvedToolNames = UnmodifiableSetView<String>(
         Set<String>.from(approvedToolNames),
       ),
       _clock = clock ?? DateTime.now,
       _tools = _indexTools(tools) {
    if (version.trim().isEmpty) {
      throw ArgumentError.value(version, 'version');
    }
    if (maxOutputBytes < 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    if (_approvedToolNames.any((name) => name.trim().isEmpty) ||
        _tools.keys.length != _approvedToolNames.length ||
        !_tools.keys.toSet().containsAll(_approvedToolNames)) {
      throw ArgumentError.value(approvedToolNames, 'approvedToolNames');
    }
    for (final tool in _tools.values) {
      if (tool.inputSchema.toolName != tool.name ||
          (tool.permission != TutorToolPermission.readLocal &&
              tool.permission != TutorToolPermission.computeLocal)) {
        throw ArgumentError.value(tool, 'tools');
      }
    }
  }

  final String version;
  final int maxOutputBytes;
  final Set<String> _approvedToolNames;
  final DateTime Function() _clock;
  final Map<String, TutorTool> _tools;

  /// Schemas for one turn policy.
  List<TutorToolSchema> schemasForTurn(TutorToolTurnPolicy policy) =>
      List<TutorToolSchema>.unmodifiable(<TutorToolSchema>[
        for (final tool in _tools.values)
          if (policy.allowedToolNames.contains(tool.name) &&
              policy.allowedPermissions.contains(tool.permission))
            tool.inputSchema,
      ]);

  /// Executes one tool request.
  Future<AppResult<TutorToolResult>> execute(TutorToolRequest request) async {
    final tool = _tools[request.toolName];
    if (tool == null ||
        !request.policy.allowedToolNames.contains(request.toolName) ||
        !request.policy.allowedPermissions.contains(tool.permission)) {
      return const AppResult<TutorToolResult>.failure(ValidationFailure());
    }

    try {
      final payload = await tool
          .execute(request.input)
          .timeout(
            request.timeout,
            onTimeout: () => throw const _TutorToolTimeout(),
          );
      return AppResult<TutorToolResult>.success(
        TutorToolResult.completed(
          payload: payload,
          provenance: tool.provenance,
          timestamp: _clock(),
          maxOutputBytes: maxOutputBytes,
        ),
      );
    } on _TutorToolTimeout {
      return AppResult<TutorToolResult>.success(
        TutorToolResult.timedOut(
          provenance: tool.provenance,
          timestamp: _clock(),
          maxOutputBytes: maxOutputBytes,
        ),
      );
    } on TutorToolInputException {
      return const AppResult<TutorToolResult>.failure(ValidationFailure());
    } catch (_) {
      return const AppResult<TutorToolResult>.failure(UnknownFailure());
    }
  }

  static Map<String, TutorTool> _indexTools(Iterable<TutorTool> tools) {
    final indexed = <String, TutorTool>{};
    for (final tool in tools) {
      if (tool.name.trim().isEmpty || indexed.containsKey(tool.name)) {
        throw ArgumentError.value(tools, 'tools');
      }
      indexed[tool.name] = tool;
    }
    return UnmodifiableMapView<String, TutorTool>(indexed);
  }
}

final class _TutorToolTimeout implements Exception {
  const _TutorToolTimeout();
}
