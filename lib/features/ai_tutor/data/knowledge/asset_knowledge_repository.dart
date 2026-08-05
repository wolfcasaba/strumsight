import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart';
import 'package:strumsight/core/logging/app_logger.dart';

import 'knowledge_codec.dart';
import 'knowledge_document.dart';
import 'knowledge_index.dart';

abstract interface class KnowledgeAssetLoader {
  Future<String> loadString(String assetPath);
}

final class RootBundleKnowledgeAssetLoader implements KnowledgeAssetLoader {
  const RootBundleKnowledgeAssetLoader();

  @override
  Future<String> loadString(String assetPath) =>
      rootBundle.loadString(assetPath);
}

abstract final class KnowledgeIndexLoadErrorCode {
  static const String malformedManifest =
      'tutorKnowledge.indexLoad.malformedManifest';
  static const String corruptDocument =
      'tutorKnowledge.indexLoad.corruptDocument';
  static const String unapprovedDocument =
      'tutorKnowledge.indexLoad.unapprovedDocument';
  static const String manifestDocumentMismatch =
      'tutorKnowledge.indexLoad.manifestDocumentMismatch';
  static const String manifestChunkMismatch =
      'tutorKnowledge.indexLoad.manifestChunkMismatch';
  static const String assetReadFailure =
      'tutorKnowledge.indexLoad.assetReadFailure';
  static const String contentHashMismatch =
      'tutorKnowledge.indexLoad.contentHashMismatch';
}

@immutable
final class KnowledgeIndexLoadResult {
  const KnowledgeIndexLoadResult._({required this.index, this.errorCode});

  const KnowledgeIndexLoadResult.loaded(KnowledgeIndex index)
    : this._(index: index);

  KnowledgeIndexLoadResult.fallback(String errorCode)
    : this._(index: KnowledgeIndex.empty(), errorCode: errorCode);

  final KnowledgeIndex index;
  final String? errorCode;

  bool get isFallback => errorCode != null;
}

final class AssetKnowledgeRepository {
  AssetKnowledgeRepository({
    required this.assetLoader,
    this.logger = const NoopAppLogger(),
    this.assetRoot = defaultAssetRoot,
  });

  AssetKnowledgeRepository.fromRootBundle({
    AppLogger logger = const NoopAppLogger(),
    String assetRoot = defaultAssetRoot,
  }) : this(
         assetLoader: const RootBundleKnowledgeAssetLoader(),
         logger: logger,
         assetRoot: assetRoot,
       );

  static const String defaultAssetRoot = 'assets/tutor_knowledge';

  final KnowledgeAssetLoader assetLoader;
  final AppLogger logger;
  final String assetRoot;

  Future<KnowledgeIndexLoadResult> loadIndex() async {
    try {
      final manifest = _decodeManifest(
        await assetLoader.loadString('$assetRoot/manifest.json'),
      );
      final documents = <KnowledgeDocument>[];
      for (final manifestDocument in manifest) {
        documents.add(await _loadDocument(manifestDocument));
      }
      return KnowledgeIndexLoadResult.loaded(
        KnowledgeIndex.fromDocuments(documents),
      );
    } on _KnowledgeIndexLoadException catch (error, stackTrace) {
      return _fallback(error.code, error, stackTrace);
    } on KnowledgeIndexException catch (error, stackTrace) {
      return _fallback(
        error.code == KnowledgeIndexErrorCode.contentHashMismatch
            ? KnowledgeIndexLoadErrorCode.contentHashMismatch
            : KnowledgeIndexLoadErrorCode.corruptDocument,
        error,
        stackTrace,
      );
    } on Object catch (error, stackTrace) {
      return _fallback(
        KnowledgeIndexLoadErrorCode.assetReadFailure,
        error,
        stackTrace,
      );
    }
  }

  Future<KnowledgeDocument> _loadDocument(
    _ManifestDocument manifestDocument,
  ) async {
    final KnowledgeDocument document;
    try {
      document = const KnowledgeCodec().decodeDocument(
        utf8.encode(
          await assetLoader.loadString(
            '$assetRoot/${manifestDocument.sourcePath}',
          ),
        ),
      );
    } on KnowledgeCodecException {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.corruptDocument,
      );
    }
    if (document.status != KnowledgeApprovalStatus.approved) {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.unapprovedDocument,
      );
    }
    if (!manifestDocument.matches(document)) {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.manifestDocumentMismatch,
      );
    }
    final chunks = const KnowledgeCodec().chunkDocument(document);
    if (!manifestDocument.matchesChunks(chunks)) {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.manifestChunkMismatch,
      );
    }
    return document;
  }

  KnowledgeIndexLoadResult _fallback(
    String code,
    Object error,
    StackTrace stackTrace,
  ) {
    logger.error(
      'tutor.knowledge_index.load_failed',
      error: error,
      stackTrace: stackTrace,
      fields: <String, Object?>{'code': code},
    );
    return KnowledgeIndexLoadResult.fallback(code);
  }

  List<_ManifestDocument> _decodeManifest(String rawManifest) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawManifest);
    } on FormatException {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.malformedManifest,
      );
    }
    if (decoded is! Map) {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.malformedManifest,
      );
    }
    final root = Map<String, Object?>.from(decoded);
    if (root['schemaVersion'] != KnowledgeCodec.manifestSchemaVersion ||
        root['documents'] is! List) {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.malformedManifest,
      );
    }
    try {
      return List<_ManifestDocument>.unmodifiable(
        (root['documents']! as List<Object?>).map(_ManifestDocument.fromJson),
      );
    } on _KnowledgeIndexLoadException {
      rethrow;
    } on Object {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.malformedManifest,
      );
    }
  }
}

final class _KnowledgeIndexLoadException implements Exception {
  const _KnowledgeIndexLoadException(this.code);

  final String code;
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
    if (value is! Map) {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.malformedManifest,
      );
    }
    final json = Map<String, Object?>.from(value);
    final chunks = json['chunks'];
    if (chunks is! List) {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.malformedManifest,
      );
    }
    final id = _requiredString(json, 'id');
    final locale = _requiredString(json, 'locale');
    final sourcePath = _requiredString(json, 'sourcePath');
    if (sourcePath != '$locale/$id.json') {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.malformedManifest,
      );
    }
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
      final manifestChunk = chunks[index];
      if (!manifestChunk.matches(chunk)) return false;
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
    if (value is! Map) {
      throw const _KnowledgeIndexLoadException(
        KnowledgeIndexLoadErrorCode.malformedManifest,
      );
    }
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
  throw const _KnowledgeIndexLoadException(
    KnowledgeIndexLoadErrorCode.malformedManifest,
  );
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw const _KnowledgeIndexLoadException(
    KnowledgeIndexLoadErrorCode.malformedManifest,
  );
}
