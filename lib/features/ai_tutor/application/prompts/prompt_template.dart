import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import '../context/context_purpose.dart';
import 'prompt_version.dart';

/// Loads the trusted prompt template selected for one tutor purpose.
abstract interface class PromptTemplateLoader {
  Future<PromptTemplate> load(ContextPurpose purpose);
}

/// Trusted system-language instructions for one tutor purpose.
@immutable
final class PromptTemplate {
  PromptTemplate({
    required this.id,
    required this.version,
    required this.locale,
    required this.intent,
    required this.template,
    required this.outputSchemaVersion,
  }) {
    if (id.trim().isEmpty || locale != 'en' || template.trim().isEmpty) {
      throw ArgumentError.value(id, 'id');
    }
    if (template.contains('<<<') || template.contains('>>>')) {
      throw ArgumentError.value(template, 'template');
    }
  }

  final String id;
  final PromptVersion version;
  final String locale;
  final ContextPurpose intent;
  final String template;
  final PromptVersion outputSchemaVersion;

  factory PromptTemplate.fromAssetJson(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Prompt template must be a JSON object.');
    }
    return PromptTemplate(
      id: _stringValue(decoded, 'id'),
      version: PromptVersion.parse(_stringValue(decoded, 'version')),
      locale: _stringValue(decoded, 'locale'),
      intent: _intentFor(_stringValue(decoded, 'intent')),
      template: _stringValue(decoded, 'template'),
      outputSchemaVersion: PromptVersion.parse(
        _stringValue(decoded, 'outputSchemaVersion'),
      ),
    );
  }
}

/// Asset-backed prompt-template loader for the tutor's fixed intents.
final class AssetPromptTemplateLoader implements PromptTemplateLoader {
  AssetPromptTemplateLoader({required this.assetBundle});

  final AssetBundle assetBundle;

  @override
  Future<PromptTemplate> load(ContextPurpose purpose) async {
    final template = PromptTemplate.fromAssetJson(
      await assetBundle.loadString(_assetPathFor(purpose)),
    );
    if (template.intent != purpose) {
      throw FormatException('Prompt template intent does not match $purpose.');
    }
    return template;
  }
}

String _assetPathFor(ContextPurpose purpose) => switch (purpose) {
  ContextPurpose.generalQuestion =>
    'assets/tutor_prompts/general_question.json',
  ContextPurpose.sessionDebrief => 'assets/tutor_prompts/session_debrief.json',
  ContextPurpose.progressReview => 'assets/tutor_prompts/progress_review.json',
  ContextPurpose.practicePlanning =>
    'assets/tutor_prompts/practice_planning.json',
  ContextPurpose.songHelp => 'assets/tutor_prompts/song_help.json',
  ContextPurpose.profileUpdate => 'assets/tutor_prompts/profile_update.json',
};

String _stringValue(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'Prompt template field $key must be a non-empty string.',
    );
  }
  return value;
}

ContextPurpose _intentFor(String value) => switch (value) {
  'generalQuestion' => ContextPurpose.generalQuestion,
  'sessionDebrief' => ContextPurpose.sessionDebrief,
  'progressReview' => ContextPurpose.progressReview,
  'practicePlanning' => ContextPurpose.practicePlanning,
  'songHelp' => ContextPurpose.songHelp,
  'profileUpdate' => ContextPurpose.profileUpdate,
  _ => throw FormatException('Unknown prompt template intent: $value'),
};
