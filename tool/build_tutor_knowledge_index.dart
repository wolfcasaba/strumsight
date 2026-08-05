import 'dart:convert';
import 'dart:io';

import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_codec.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_document.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_index.dart';

void main(List<String> arguments) {
  if (arguments.length > 2) {
    throw ArgumentError('Expected [content root] [output file].');
  }
  final contentRoot = Directory(
    arguments.isEmpty ? 'assets/tutor_knowledge' : arguments.first,
  );
  final outputFile = File(
    arguments.length == 2 ? arguments[1] : 'build/tutor-knowledge-index.json',
  );
  buildTutorKnowledgeIndex(contentRoot: contentRoot, outputFile: outputFile);
}

void buildTutorKnowledgeIndex({
  required Directory contentRoot,
  required File outputFile,
}) {
  final index = KnowledgeIndex.fromDocuments(
    _readManifestDocuments(contentRoot),
  );
  final output = <String, Object?>{
    'schemaVersion': KnowledgeCodec.manifestSchemaVersion,
    'entries': <Object?>[
      for (final entry in index.entries)
        <String, Object?>{
          'documentId': entry.document.id,
          'locale': entry.document.locale,
          'skill': entry.document.skill.name,
          'difficulty': entry.document.difficulty.name,
          'knowledgeVersion': entry.document.version,
          'title': entry.document.title,
          'contentHash': entry.document.contentHash,
          'chunkIndex': entry.chunk.index,
          'chunk': entry.chunk.content,
          'chunkHash': entry.chunk.contentHash,
        },
    ],
  };
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsBytesSync(utf8.encode(jsonEncode(output)), flush: true);
}

List<KnowledgeDocument> _readManifestDocuments(Directory contentRoot) {
  if (!contentRoot.existsSync()) {
    throw ArgumentError.value(contentRoot.path, 'contentRoot', 'Must exist.');
  }
  final manifest = _readManifest(File('${contentRoot.path}/manifest.json'));
  final codec = KnowledgeCodec();
  final documents = <KnowledgeDocument>[];
  for (final manifestDocument in manifest) {
    final document = codec.decodeDocument(
      File(
        '${contentRoot.path}/${manifestDocument.sourcePath}',
      ).readAsBytesSync(),
    );
    if (document.status != KnowledgeApprovalStatus.approved ||
        !manifestDocument.matches(document) ||
        !manifestDocument.matchesChunks(codec.chunkDocument(document))) {
      throw StateError('Manifest does not match approved source content.');
    }
    documents.add(document);
  }
  return List<KnowledgeDocument>.unmodifiable(documents);
}

List<_ManifestDocument> _readManifest(File manifestFile) {
  final Object? decoded;
  try {
    decoded = jsonDecode(manifestFile.readAsStringSync());
  } on FormatException {
    throw StateError('Manifest is not valid JSON.');
  }
  if (decoded is! Map) throw StateError('Manifest is not an object.');
  final root = Map<String, Object?>.from(decoded);
  final documents = root['documents'];
  if (root['schemaVersion'] != KnowledgeCodec.manifestSchemaVersion ||
      documents is! List) {
    throw StateError('Manifest has an unsupported schema.');
  }
  return List<_ManifestDocument>.unmodifiable(
    documents.map(_ManifestDocument.fromJson),
  );
}

final class _ManifestDocument {
  const _ManifestDocument({
    required this.id,
    required this.locale,
    required this.skill,
    required this.difficulty,
    required this.license,
    required this.version,
    required this.contentHash,
    required this.sourcePath,
    required this.chunks,
  });

  factory _ManifestDocument.fromJson(Object? value) {
    if (value is! Map) throw StateError('Manifest document is not an object.');
    final json = Map<String, Object?>.from(value);
    final id = _requiredString(json, 'id');
    final locale = _requiredString(json, 'locale');
    final sourcePath = _requiredString(json, 'sourcePath');
    if (sourcePath != '$locale/$id.json') {
      throw StateError('Manifest document has an invalid source path.');
    }
    final chunks = json['chunks'];
    if (chunks is! List) throw StateError('Manifest chunks are missing.');
    return _ManifestDocument(
      id: id,
      locale: locale,
      skill: _requiredString(json, 'skill'),
      difficulty: _requiredString(json, 'difficulty'),
      license: _requiredString(json, 'license'),
      version: _requiredInt(json, 'version'),
      contentHash: _requiredString(json, 'contentHash'),
      sourcePath: sourcePath,
      chunks: List<_ManifestChunk>.unmodifiable(
        chunks.map(_ManifestChunk.fromJson),
      ),
    );
  }

  final String id;
  final String locale;
  final String skill;
  final String difficulty;
  final String license;
  final int version;
  final String contentHash;
  final String sourcePath;
  final List<_ManifestChunk> chunks;

  bool matches(KnowledgeDocument document) =>
      id == document.id &&
      locale == document.locale &&
      skill == document.skill.name &&
      difficulty == document.difficulty.name &&
      license == document.license &&
      version == document.version &&
      contentHash == document.contentHash;

  bool matchesChunks(List<KnowledgeChunk> documentChunks) {
    if (chunks.length != documentChunks.length) return false;
    for (final (index, chunk) in documentChunks.indexed) {
      if (!chunks[index].matches(chunk)) return false;
    }
    return true;
  }
}

final class _ManifestChunk {
  const _ManifestChunk({
    required this.id,
    required this.index,
    required this.contentHash,
  });

  factory _ManifestChunk.fromJson(Object? value) {
    if (value is! Map) throw StateError('Manifest chunk is not an object.');
    final json = Map<String, Object?>.from(value);
    return _ManifestChunk(
      id: _requiredString(json, 'id'),
      index: _requiredInt(json, 'index'),
      contentHash: _requiredString(json, 'contentHash'),
    );
  }

  final String id;
  final int index;
  final String contentHash;

  bool matches(KnowledgeChunk chunk) =>
      id == chunk.id &&
      index == chunk.index &&
      contentHash == chunk.contentHash;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw StateError('Manifest field $key is invalid.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw StateError('Manifest field $key is invalid.');
}
