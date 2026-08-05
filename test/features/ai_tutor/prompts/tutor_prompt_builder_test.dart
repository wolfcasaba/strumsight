import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_assembler.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_template.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/tutor_output_schema.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/tutor_prompt_builder.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_response_mode.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_source_ref.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_registry.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_request.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final builder = TutorPromptBuilder(
    templateLoader: AssetPromptTemplateLoader(assetBundle: rootBundle),
  );

  test(
    'renders the required layers in order from redacted context and registry schemas',
    () async {
      final prompt = await builder.build(
        _request(
          context: _redactedSnapshot(),
          registry: _registry(),
          policy: TutorToolTurnPolicy(
            allowedToolNames: const <String>{'allowedRead'},
            allowedPermissions: const <TutorToolPermission>{
              TutorToolPermission.readLocal,
            },
          ),
          trustedSources: const <TutorSourceRef>[
            TutorSourceRef(
              sourceId: 'knowledge.rhythm',
              title: 'Count steady eighth notes',
              locale: 'en',
              topic: 'rhythm',
              knowledgeVersion: 2,
              chunkIndex: 0,
              chunkHash: 'fixture-hash',
            ),
          ],
          importedContent: const <PromptUntrustedContent>[
            PromptUntrustedContent.imported('Song title: Eight Beats'),
          ],
          conversationHistory: const <PromptUntrustedContent>[
            PromptUntrustedContent.conversation('I rush after the chorus.'),
          ],
          userRequest: 'How can I keep the eighth notes steady?',
        ),
      );

      final text = prompt.text;
      expect(
        _sectionStarts(text),
        orderedEquals(<String>[
          '<<<PRODUCT_POLICY>>>',
          '<<<SAFETY_POLICY>>>',
          '<<<TUTOR_PEDAGOGY_POLICY>>>',
          '<<<TOOL_CONTRACT_SUMMARY>>>',
          '<<<STRUCTURED_USER_CONTEXT>>>',
          '<<<TRUSTED_KNOWLEDGE>>>',
          '<<<UNTRUSTED_USER_IMPORTED_CONTENT>>>',
          '<<<UNTRUSTED_CONVERSATION_HISTORY>>>',
          '<<<UNTRUSTED_CURRENT_USER_REQUEST>>>',
          '<<<REQUIRED_OUTPUT_SCHEMA>>>',
        ]),
      );
      expect(text, contains('Response locale: hu-HU.'));
      expect(text, contains('"name":"allowedRead"'));
      expect(text, isNot(contains('"name":"notAllowed"')));
      expect(text, contains('knowledge.rhythm#1'));
      expect(text, contains('"schemaVersion":"v1"'));
      expect(text, isNot(contains('should-never-leave-device')));
      expect(text, isNot(contains('[0,1,-1]')));
      expect(text, isNot(contains('step-by-step')));
      expect(text, isNot(contains('chain-of-thought')));
      expect(prompt.version.templateId, 'general-question');
      expect(prompt.version.promptVersion.value, 'v1');
      expect(prompt.version.outputSchemaVersion, TutorOutputSchema.v1.version);
      expect(prompt.version.toolRegistryVersion, 'fixture.registry.v1');
    },
  );

  test(
    'uses the registry turn-policy intersection without a builder allowlist',
    () async {
      final prompt = await builder.build(
        _request(
          context: _redactedSnapshot(),
          registry: _registry(),
          policy: TutorToolTurnPolicy(
            allowedToolNames: const <String>{'allowedRead', 'notAllowed'},
            allowedPermissions: const <TutorToolPermission>{
              TutorToolPermission.readLocal,
            },
          ),
        ),
      );

      final toolSection = _section(
        text: prompt.text,
        name: 'TOOL_CONTRACT_SUMMARY',
      );
      expect(toolSection, contains('"name":"allowedRead"'));
      expect(toolSection, isNot(contains('"name":"notAllowed"')));
    },
  );

  test('publishes only the v1 structured response fields', () {
    final schema = TutorOutputSchema.v1;

    expect(schema.version.value, 'v1');
    expect(schema.canonicalJson, contains('"answerBlocks"'));
    expect(schema.canonicalJson, contains('"claims"'));
    expect(schema.canonicalJson, contains('"actions"'));
    expect(schema.canonicalJson, contains('"followUpSuggestions"'));
    expect(schema.canonicalJson, contains('"safetyNotices"'));
    expect(schema.canonicalJson, contains('"memoryCandidates"'));
    expect(schema.canonicalJson, isNot(contains('reasoning')));
  });
}

TutorPromptRequest _request({
  required TutorContextSnapshot context,
  required TutorToolRegistry registry,
  required TutorToolTurnPolicy policy,
  Iterable<TutorSourceRef> trustedSources = const <TutorSourceRef>[],
  Iterable<PromptUntrustedContent> importedContent =
      const <PromptUntrustedContent>[],
  Iterable<PromptUntrustedContent> conversationHistory =
      const <PromptUntrustedContent>[],
  String userRequest = '',
}) => TutorPromptRequest(
  context: context,
  responseLocale: 'hu-HU',
  responseMode: TutorResponseMode.standard,
  toolRegistry: registry,
  toolPolicy: policy,
  trustedSources: trustedSources,
  importedContent: importedContent,
  conversationHistory: conversationHistory,
  userRequest: userRequest,
);

TutorContextSnapshot _redactedSnapshot() =>
    const TutorContextAssembler().assemble(
      requestId: 'request-42',
      createdAt: DateTime.utc(2026, 8, 5, 12),
      purpose: ContextPurpose.generalQuestion,
      fields: <TutorContextField>[
        TutorContextField.available(
          key: TutorContextFieldKey.studentProfile,
          values: <String, Object?>{
            'displayName': 'Nora',
            'accessToken': 'should-never-leave-device',
            'pcmSamples': <Object?>[0, 1, -1],
          },
          provenance: ContextProvenance(
            sourceFeature: ContextSourceFeature.aiTutor,
            schemaVersion: 'profile.v1',
          ),
        ),
      ],
    );

TutorToolRegistry _registry() => TutorToolRegistry(
  version: 'fixture.registry.v1',
  tools: <TutorTool>[
    const _FixtureTool(
      name: 'allowedRead',
      permission: TutorToolPermission.readLocal,
    ),
    const _FixtureTool(
      name: 'notAllowed',
      permission: TutorToolPermission.computeLocal,
    ),
  ],
  approvedToolNames: const <String>{'allowedRead', 'notAllowed'},
  maxOutputBytes: 128,
);

List<String> _sectionStarts(String text) => <String>[
  for (final line in text.split('\n'))
    if (line.startsWith('<<<') && !line.startsWith('<<<END_')) line,
];

String _section({required String text, required String name}) {
  final start = '<<<$name>>>';
  final end = '<<<END_$name>>>';
  return text.substring(text.indexOf(start) + start.length, text.indexOf(end));
}

final class _FixtureTool implements TutorTool {
  const _FixtureTool({required this.name, required this.permission});

  @override
  final String name;

  @override
  final TutorToolPermission permission;

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
    source: 'test.fixture',
    schemaVersion: 'fixture.v1',
  );

  @override
  Future<TutorToolPayload> execute(TutorToolInput input) async =>
      TutorToolPayload(const <String, Object?>{});
}
