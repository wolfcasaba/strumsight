import 'dart:convert';
import 'dart:io';

// `path` ships with the Flutter SDK and is resolved for every target of this
// repo, but it is not listed in pubspec.yaml, so the lint below would make
// `flutter analyze` (the gate) non-zero on an otherwise correct import.
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;

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
  final manifestPath = p.join(contentRoot.absolute.path, 'manifest.json');
  final files = <File>[
    for (final entity in contentRoot.listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.json') &&
          !isExcludedManifestPath(
            entity.absolute.path,
            outputPath: outputPath,
            manifestPath: manifestPath,
          ))
        entity,
  ];
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

/// Whether [candidate] names the same file as the manifest this run is about
/// to write ([outputPath]) or as the conventional `manifest.json` sitting in
/// the content root ([manifestPath]).
///
/// The comparison goes through `package:path`'s [p.Context.equals] instead of
/// `==` on the raw strings. `listSync` reports paths with the platform
/// separator while the two excluded paths are built by joining, so on Windows
/// the `/`-spelled `manifest.json` never matched the `\`-spelled listing entry
/// and a previous run's output was decoded as if it were a knowledge document.
/// `equals` normalises the separators and any `.` / `..` segment, and in the
/// windows context it also compares case-insensitively — which is that
/// platform's own file-identity rule, so `Assets/...` and `assets/...` name
/// one file there and two files on POSIX.
///
/// [context] exists so the rule can be exercised for both platforms from any
/// host; production callers leave it unset and get [p.context].
bool isExcludedManifestPath(
  String candidate, {
  required String outputPath,
  required String manifestPath,
  p.Context? context,
}) {
  final resolved = context ?? p.context;
  return resolved.equals(candidate, outputPath) ||
      resolved.equals(candidate, manifestPath);
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
