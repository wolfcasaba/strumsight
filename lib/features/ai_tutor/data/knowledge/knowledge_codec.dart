import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'knowledge_document.dart';

final class KnowledgeCodecException implements Exception {
  const KnowledgeCodecException(this.code, {this.field});

  final String code;
  final String? field;

  @override
  String toString() =>
      'KnowledgeCodecException($code${field == null ? '' : ', field: $field'})';
}

abstract final class KnowledgeCodecErrorCode {
  static const String malformedJson = 'tutorKnowledge.codec.malformedJson';
  static const String notAnObject = 'tutorKnowledge.codec.notAnObject';
  static const String schemaVersionMissing =
      'tutorKnowledge.codec.schemaVersion.missing';
  static const String schemaVersionUnknown =
      'tutorKnowledge.codec.schemaVersion.unknown';
  static const String fieldMissing = 'tutorKnowledge.codec.field.missing';
  static const String fieldInvalid = 'tutorKnowledge.codec.field.invalid';
  static const String skillUnknown = 'tutorKnowledge.codec.skill.unknown';
  static const String difficultyUnknown =
      'tutorKnowledge.codec.difficulty.unknown';
  static const String statusUnknown = 'tutorKnowledge.codec.status.unknown';
}

/// Deterministic JSON codec and chunker for tutor knowledge documents.
final class KnowledgeCodec {
  const KnowledgeCodec();

  static const int manifestSchemaVersion = 1;

  List<int> encodeDocument(KnowledgeDocument document) =>
      utf8.encode(jsonEncode(_documentToMap(document)));

  KnowledgeDocument decodeDocument(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const KnowledgeCodecException(
        KnowledgeCodecErrorCode.malformedJson,
      );
    }
    final root = _asObjectMap(decoded);
    final schemaVersion = _requiredInt(root, 'schemaVersion');
    if (schemaVersion != KnowledgeDocument.currentSchemaVersion) {
      throw const KnowledgeCodecException(
        KnowledgeCodecErrorCode.schemaVersionUnknown,
        field: 'schemaVersion',
      );
    }
    try {
      return KnowledgeDocument(
        schemaVersion: schemaVersion,
        id: _requiredString(root, 'id'),
        locale: _requiredString(root, 'locale'),
        skill: _enumValue(
          _requiredString(root, 'skill'),
          KnowledgeSkill.values,
          KnowledgeCodecErrorCode.skillUnknown,
          'skill',
        ),
        difficulty: _enumValue(
          _requiredString(root, 'difficulty'),
          KnowledgeDifficulty.values,
          KnowledgeCodecErrorCode.difficultyUnknown,
          'difficulty',
        ),
        license: _requiredString(root, 'license'),
        version: _requiredInt(root, 'version'),
        status: _enumValue(
          _requiredString(root, 'status'),
          KnowledgeApprovalStatus.values,
          KnowledgeCodecErrorCode.statusUnknown,
          'status',
        ),
        title: _requiredString(root, 'title'),
        body: _requiredString(root, 'body'),
        contentHash: _requiredString(root, 'contentHash'),
      );
    } on KnowledgeDocumentValidationException {
      throw const KnowledgeCodecException(KnowledgeCodecErrorCode.fieldInvalid);
    }
  }

  List<KnowledgeChunk> chunkDocument(KnowledgeDocument document) =>
      List<KnowledgeChunk>.unmodifiable(<KnowledgeChunk>[
        for (final (index, content) in _paragraphs(document.body).indexed)
          KnowledgeChunk(
            documentId: document.id,
            index: index,
            content: content,
            contentHash: contentHashForChunk(
              documentId: document.id,
              index: index,
              content: content,
            ),
          ),
      ]);

  static String contentHashForDocument({
    required String title,
    required String body,
  }) => _hash('title:$title\nbody:$body');

  static String contentHashForChunk({
    required String documentId,
    required int index,
    required String content,
  }) => _hash('documentId:$documentId\nindex:$index\ncontent:$content');
}

Map<String, Object?> _documentToMap(KnowledgeDocument document) =>
    <String, Object?>{
      'schemaVersion': document.schemaVersion,
      'id': document.id,
      'locale': document.locale,
      'skill': document.skill.name,
      'difficulty': document.difficulty.name,
      'license': document.license,
      'version': document.version,
      'status': document.status.name,
      'title': document.title,
      'body': document.body,
      'contentHash': document.contentHash,
    };

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is! Map) {
    throw const KnowledgeCodecException(KnowledgeCodecErrorCode.notAnObject);
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const KnowledgeCodecException(KnowledgeCodecErrorCode.notAnObject);
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Map<String, Object?> root, String field) {
  final value = root[field];
  if (value == null) {
    throw KnowledgeCodecException(
      KnowledgeCodecErrorCode.fieldMissing,
      field: field,
    );
  }
  if (value is! String) {
    throw KnowledgeCodecException(
      KnowledgeCodecErrorCode.fieldInvalid,
      field: field,
    );
  }
  return value;
}

int _requiredInt(Map<String, Object?> root, String field) {
  final value = root[field];
  if (value == null) {
    throw KnowledgeCodecException(
      field == 'schemaVersion'
          ? KnowledgeCodecErrorCode.schemaVersionMissing
          : KnowledgeCodecErrorCode.fieldMissing,
      field: field,
    );
  }
  if (value is! int) {
    throw KnowledgeCodecException(
      KnowledgeCodecErrorCode.fieldInvalid,
      field: field,
    );
  }
  return value;
}

T _enumValue<T extends Enum>(
  String value,
  List<T> values,
  String errorCode,
  String field,
) {
  for (final candidate in values) {
    if (candidate.name == value) {
      return candidate;
    }
  }
  throw KnowledgeCodecException(errorCode, field: field);
}

Iterable<String> _paragraphs(String body) sync* {
  for (final paragraph in body.split('\n\n')) {
    final normalized = paragraph.trim();
    if (normalized.isNotEmpty) {
      yield normalized;
    }
  }
}

String _hash(String content) =>
    crypto.sha256.convert(utf8.encode(content)).toString();
