import 'package:meta/meta.dart';

enum KnowledgeSkill { rhythm, chord, technique, practice, safety }

enum KnowledgeDifficulty { beginner, intermediate, advanced }

enum KnowledgeApprovalStatus { approved, reviewNeeded, rejected }

abstract final class KnowledgeDocumentValidationCode {
  static const String schemaVersion = 'tutorKnowledge.document.schemaVersion';
  static const String id = 'tutorKnowledge.document.id';
  static const String locale = 'tutorKnowledge.document.locale';
  static const String license = 'tutorKnowledge.document.license';
  static const String version = 'tutorKnowledge.document.version';
  static const String title = 'tutorKnowledge.document.title';
  static const String body = 'tutorKnowledge.document.body';
  static const String contentHash = 'tutorKnowledge.document.contentHash';
  static const String chunkIndex = 'tutorKnowledge.chunk.index';
  static const String chunkContent = 'tutorKnowledge.chunk.content';
  static const String chunkHash = 'tutorKnowledge.chunk.contentHash';
}

final class KnowledgeDocumentValidationException implements Exception {
  const KnowledgeDocumentValidationException(this.code);

  final String code;

  @override
  String toString() => 'KnowledgeDocumentValidationException($code)';
}

@immutable
final class KnowledgeDocument {
  KnowledgeDocument({
    required this.schemaVersion,
    required this.id,
    required this.locale,
    required this.skill,
    required this.difficulty,
    required this.license,
    required this.version,
    required this.status,
    required this.title,
    required this.body,
    required this.contentHash,
  }) {
    if (schemaVersion != currentSchemaVersion) {
      throw const KnowledgeDocumentValidationException(
        KnowledgeDocumentValidationCode.schemaVersion,
      );
    }
    _validateId(id, KnowledgeDocumentValidationCode.id);
    if (!_localePattern.hasMatch(locale)) {
      throw const KnowledgeDocumentValidationException(
        KnowledgeDocumentValidationCode.locale,
      );
    }
    if (license.trim().isEmpty || license != license.trim()) {
      throw const KnowledgeDocumentValidationException(
        KnowledgeDocumentValidationCode.license,
      );
    }
    if (version < 1) {
      throw const KnowledgeDocumentValidationException(
        KnowledgeDocumentValidationCode.version,
      );
    }
    if (title.trim().isEmpty || title != title.trim() || title.contains('\n')) {
      throw const KnowledgeDocumentValidationException(
        KnowledgeDocumentValidationCode.title,
      );
    }
    if (body.trim().isEmpty || body != body.trim() || body.contains('\r')) {
      throw const KnowledgeDocumentValidationException(
        KnowledgeDocumentValidationCode.body,
      );
    }
    _validateHash(contentHash, KnowledgeDocumentValidationCode.contentHash);
  }

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String id;
  final String locale;
  final KnowledgeSkill skill;
  final KnowledgeDifficulty difficulty;
  final String license;
  final int version;
  final KnowledgeApprovalStatus status;
  final String title;
  final String body;
  final String contentHash;

  @override
  bool operator ==(Object other) =>
      other is KnowledgeDocument &&
      schemaVersion == other.schemaVersion &&
      id == other.id &&
      locale == other.locale &&
      skill == other.skill &&
      difficulty == other.difficulty &&
      license == other.license &&
      version == other.version &&
      status == other.status &&
      title == other.title &&
      body == other.body &&
      contentHash == other.contentHash;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    id,
    locale,
    skill,
    difficulty,
    license,
    version,
    status,
    title,
    body,
    contentHash,
  );
}

@immutable
final class KnowledgeChunk {
  KnowledgeChunk({
    required this.documentId,
    required this.index,
    required this.content,
    required this.contentHash,
  }) {
    _validateId(documentId, KnowledgeDocumentValidationCode.id);
    if (index < 0) {
      throw const KnowledgeDocumentValidationException(
        KnowledgeDocumentValidationCode.chunkIndex,
      );
    }
    if (content.trim().isEmpty || content != content.trim()) {
      throw const KnowledgeDocumentValidationException(
        KnowledgeDocumentValidationCode.chunkContent,
      );
    }
    _validateHash(contentHash, KnowledgeDocumentValidationCode.chunkHash);
  }

  final String documentId;
  final int index;
  final String content;
  final String contentHash;

  String get id => '$documentId#${index + 1}';

  @override
  bool operator ==(Object other) =>
      other is KnowledgeChunk &&
      documentId == other.documentId &&
      index == other.index &&
      content == other.content &&
      contentHash == other.contentHash;

  @override
  int get hashCode => Object.hash(documentId, index, content, contentHash);
}

final RegExp _documentIdPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
final RegExp _localePattern = RegExp(r'^[a-z]{2}(?:-[A-Z]{2})?$');
final RegExp _hashPattern = RegExp(r'^[a-f0-9]{64}$');

void _validateId(String value, String code) {
  if (!_documentIdPattern.hasMatch(value)) {
    throw KnowledgeDocumentValidationException(code);
  }
}

void _validateHash(String value, String code) {
  if (!_hashPattern.hasMatch(value)) {
    throw KnowledgeDocumentValidationException(code);
  }
}
