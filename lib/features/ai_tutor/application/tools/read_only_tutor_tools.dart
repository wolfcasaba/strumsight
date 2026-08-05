import 'package:strumsight/features/ai_tutor/application/context/redaction_report.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_registry.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_result.dart';

/// Initial local tutor tools.
abstract final class ReadOnlyTutorTools {
  static const String registryVersion = 'ai_tutor.read_only_tools.v1';
  static const String getContextFieldName = 'getContextField';
  static const String summarizeContextName = 'summarizeContext';

  static const Set<String> safeToolNames = <String>{
    getContextFieldName,
    summarizeContextName,
  };

  /// Builds the tools for one context snapshot.
  static List<TutorTool> toolsFor(TutorContextSnapshot snapshot) =>
      List<TutorTool>.unmodifiable(<TutorTool>[
        _GetContextFieldTool(snapshot),
        _SummarizeContextTool(snapshot),
      ]);

  /// Builds a registry for one context snapshot.
  static TutorToolRegistry registryFor({
    required TutorContextSnapshot snapshot,
    int maxOutputBytes = 4096,
    DateTime Function()? clock,
  }) => TutorToolRegistry(
    version: registryVersion,
    tools: toolsFor(snapshot),
    approvedToolNames: safeToolNames,
    maxOutputBytes: maxOutputBytes,
    clock: clock,
  );
}

final class _GetContextFieldTool implements TutorTool {
  _GetContextFieldTool(this._snapshot);

  final TutorContextSnapshot _snapshot;

  @override
  String get name => ReadOnlyTutorTools.getContextFieldName;

  @override
  TutorToolPermission get permission => TutorToolPermission.readLocal;

  @override
  TutorToolSchema get inputSchema => TutorToolSchema(
    toolName: name,
    fields: const <TutorToolSchemaField>[
      TutorToolSchemaField(
        name: 'field',
        type: TutorToolSchemaValueType.string,
        isRequired: true,
      ),
    ],
  );

  @override
  TutorToolProvenance get provenance => const TutorToolProvenance(
    source: 'tutor.context_snapshot',
    schemaVersion: 'tutor.context_snapshot.v1',
  );

  @override
  Future<TutorToolPayload> execute(TutorToolInput input) async {
    if (input.values.length != 1 || input.values['field'] is! String) {
      throw const TutorToolInputException();
    }
    final fieldName = input.values['field'] as String;
    final fieldKey = TutorContextFieldKey.values.where(
      (key) => key.name == fieldName,
    );
    if (fieldKey.length != 1) throw const TutorToolInputException();
    final fields = _snapshot.fields.where(
      (field) => field.key == fieldKey.single,
    );
    if (fields.length != 1) throw const TutorToolInputException();

    final redacted = const ContextRedactor().redact(fields.single);
    return TutorToolPayload(<String, Object?>{
      'field': redacted.field.toJson(),
      'redactionReport': redacted.report.toJson(),
    });
  }
}

final class _SummarizeContextTool implements TutorTool {
  _SummarizeContextTool(this._snapshot);

  final TutorContextSnapshot _snapshot;

  @override
  String get name => ReadOnlyTutorTools.summarizeContextName;

  @override
  TutorToolPermission get permission => TutorToolPermission.computeLocal;

  @override
  TutorToolSchema get inputSchema =>
      TutorToolSchema(toolName: name, fields: const <TutorToolSchemaField>[]);

  @override
  TutorToolProvenance get provenance => const TutorToolProvenance(
    source: 'tutor.context_snapshot',
    schemaVersion: 'tutor.context_snapshot.v1',
  );

  @override
  Future<TutorToolPayload> execute(TutorToolInput input) async {
    if (input.values.isNotEmpty) throw const TutorToolInputException();
    return TutorToolPayload(<String, Object?>{
      'fieldCount': _snapshot.fields.length,
      'availableFields': <String>[
        for (final field in _snapshot.fields) field.key.name,
      ],
      'truncatedFields': <String>[
        for (final field in _snapshot.truncatedFields) field.name,
      ],
      'redactionCount': _snapshot.redactionReport.entries.length,
    });
  }
}
