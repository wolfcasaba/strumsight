import 'dart:convert';
import 'dart:io';

import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_codec.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_document.dart';

abstract final class KnowledgeManifestErrorCode {
  static const String duplicateId = 'tutorKnowledge.manifest.duplicateId';
  static const String missingLicense = 'tutorKnowledge.manifest.missingLicense';
  static const String hashMismatch = 'tutorKnowledge.manifest.hashMismatch';
  static const String corruptContent = 'tutorKnowledge.manifest.corruptContent';
}

final class KnowledgeManifestException implements Exception {
  const KnowledgeManifestException(this.code, {this.path});

  final String code;
  final String? path;

  @override
  String toString() =>
      'KnowledgeManifestException($code${path == null ? '' : ', path: $path'})';
}

void main(List<String> arguments) {
  if (arguments.length > 2) {
    throw ArgumentError('Expected [content root] [output file].');
  }
  final contentRoot = Directory(
    arguments.isEmpty ? 'assets/tutor_knowledge' : arguments.first,
  );
  final outputFile = File(
    arguments.length == 2
        ? arguments[1]
        : '${contentRoot.path}${Platform.pathSeparator}manifest.json',
  );
  buildTutorKnowledgeManifest(contentRoot: contentRoot, outputFile: outputFile);
}

void buildTutorKnowledgeManifest({
  required Directory contentRoot,
  required File outputFile,
}) {
  final codec = KnowledgeCodec();
  final documents = <_SourceDocument>[];
  final documentIds = <String>{};
  for (final sourceFile in _contentFiles(contentRoot, outputFile)) {
    final rawContent = _readContent(sourceFile);
    final rawDocument = _decodeRawDocument(rawContent, sourceFile.path);
    final license = rawDocument['license'];
    if (license is! String || license.trim().isEmpty) {
      throw KnowledgeManifestException(
        KnowledgeManifestErrorCode.missingLicense,
        path: sourceFile.path,
      );
    }

    final KnowledgeDocument document;
    try {
      document = codec.decodeDocument(rawContent);
    } on KnowledgeCodecException {
      throw KnowledgeManifestException(
        KnowledgeManifestErrorCode.corruptContent,
        path: sourceFile.path,
      );
    }
    if (!documentIds.add(document.id)) {
      throw KnowledgeManifestException(
        KnowledgeManifestErrorCode.duplicateId,
        path: sourceFile.path,
      );
    }
    final recomputedHash = KnowledgeCodec.contentHashForDocument(
      title: document.title,
      body: document.body,
    );
    if (recomputedHash != document.contentHash) {
      throw KnowledgeManifestException(
        KnowledgeManifestErrorCode.hashMismatch,
        path: sourceFile.path,
      );
    }
    documents.add(
      _SourceDocument(
        document: document,
        sourcePath: _relativeAssetPath(contentRoot, sourceFile),
      ),
    );
  }

  documents.sort(
    (left, right) => left.document.id.compareTo(right.document.id),
  );
  final approvedDocuments = <_SourceDocument>[
    for (final sourceDocument in documents)
      if (sourceDocument.document.status == KnowledgeApprovalStatus.approved)
        sourceDocument,
  ];
  final manifest = <String, Object?>{
    'schemaVersion': KnowledgeCodec.manifestSchemaVersion,
    'documents': <Object?>[
      for (final sourceDocument in approvedDocuments)
        _manifestDocument(codec, sourceDocument),
    ],
  };
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsBytesSync(utf8.encode(jsonEncode(manifest)), flush: true);
}

List<File> _contentFiles(Directory contentRoot, File outputFile) {
  if (!contentRoot.existsSync()) {
    throw KnowledgeManifestException(KnowledgeManifestErrorCode.corruptContent);
  }
  final outputPath = outputFile.absolute.path;
  final manifestPath = File('${contentRoot.path}/manifest.json').absolute.path;
  final files = <File>[
    for (final entity in contentRoot.listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.json') &&
          entity.absolute.path != outputPath &&
          entity.absolute.path != manifestPath)
        entity,
  ];
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

List<int> _readContent(File sourceFile) {
  try {
    return sourceFile.readAsBytesSync();
  } on FileSystemException {
    throw KnowledgeManifestException(
      KnowledgeManifestErrorCode.corruptContent,
      path: sourceFile.path,
    );
  }
}

Map<String, Object?> _decodeRawDocument(List<int> bytes, String path) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw KnowledgeManifestException(
      KnowledgeManifestErrorCode.corruptContent,
      path: path,
    );
  }
  if (decoded is! Map) {
    throw KnowledgeManifestException(
      KnowledgeManifestErrorCode.corruptContent,
      path: path,
    );
  }
  final result = <String, Object?>{};
  for (final entry in decoded.entries) {
    if (entry.key is! String) {
      throw KnowledgeManifestException(
        KnowledgeManifestErrorCode.corruptContent,
        path: path,
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

Map<String, Object?> _manifestDocument(
  KnowledgeCodec codec,
  _SourceDocument sourceDocument,
) {
  final document = sourceDocument.document;
  final chunks = codec.chunkDocument(document);
  return <String, Object?>{
    'id': document.id,
    'locale': document.locale,
    'skill': document.skill.name,
    'difficulty': document.difficulty.name,
    'license': document.license,
    'version': document.version,
    'contentHash': document.contentHash,
    'sourcePath': sourceDocument.sourcePath,
    'chunks': <Object?>[
      for (final chunk in chunks)
        <String, Object?>{
          'id': chunk.id,
          'index': chunk.index,
          'contentHash': chunk.contentHash,
        },
    ],
  };
}

String _relativeAssetPath(Directory contentRoot, File sourceFile) {
  final rootPath = contentRoot.absolute.path;
  final sourcePath = sourceFile.absolute.path;
  return sourcePath
      .substring(rootPath.length + 1)
      .replaceAll(Platform.pathSeparator, '/');
}

final class _SourceDocument {
  const _SourceDocument({required this.document, required this.sourcePath});

  final KnowledgeDocument document;
  final String sourcePath;
}
