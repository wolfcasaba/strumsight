import 'dart:convert';

import 'package:meta/meta.dart';

import 'prompt_version.dart';

/// Structured tutor-response schema emitted by a prompt build.
@immutable
final class TutorOutputSchema {
  const TutorOutputSchema._(this.version);

  static const TutorOutputSchema v1 = TutorOutputSchema._(PromptVersion.v1);

  final PromptVersion version;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': version.value,
    'type': 'object',
    'additionalProperties': false,
    'required': <String>[
      'answerBlocks',
      'claims',
      'actions',
      'followUpSuggestions',
      'safetyNotices',
      'memoryCandidates',
    ],
    'properties': <String, Object?>{
      'answerBlocks': <String, Object?>{'type': 'array'},
      'claims': <String, Object?>{'type': 'array'},
      'actions': <String, Object?>{'type': 'array'},
      'followUpSuggestions': <String, Object?>{'type': 'array'},
      'safetyNotices': <String, Object?>{'type': 'array'},
      'memoryCandidates': <String, Object?>{'type': 'array'},
    },
  };

  String get canonicalJson => jsonEncode(toJson());
}
