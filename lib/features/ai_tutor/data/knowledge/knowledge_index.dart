import 'package:meta/meta.dart';

import 'knowledge_codec.dart';
import 'knowledge_document.dart';

abstract final class KnowledgeIndexErrorCode {
  static const String contentHashMismatch =
      'tutorKnowledge.index.contentHashMismatch';
  static const String chunkDocumentMismatch =
      'tutorKnowledge.index.chunkDocumentMismatch';
  static const String chunkContentMismatch =
      'tutorKnowledge.index.chunkContentMismatch';
}

final class KnowledgeIndexException implements Exception {
  const KnowledgeIndexException(this.code);

  final String code;

  @override
  String toString() => 'KnowledgeIndexException($code)';
}

@immutable
final class KnowledgeIndexEntry {
  KnowledgeIndexEntry({required this.document, required this.chunk}) {
    if (document.id != chunk.documentId) {
      throw const KnowledgeIndexException(
        KnowledgeIndexErrorCode.chunkDocumentMismatch,
      );
    }
  }

  final KnowledgeDocument document;
  final KnowledgeChunk chunk;
}

@immutable
final class KnowledgeIndex {
  KnowledgeIndex({required Iterable<KnowledgeIndexEntry> entries})
    : _entries = _canonicalizeEntries(entries);

  const KnowledgeIndex.empty() : _entries = const <KnowledgeIndexEntry>[];

  final List<KnowledgeIndexEntry> _entries;

  List<KnowledgeIndexEntry> get entries => _entries;

  factory KnowledgeIndex.fromDocuments(
    Iterable<KnowledgeDocument> documents, {
    KnowledgeCodec codec = const KnowledgeCodec(),
  }) {
    final entries = <KnowledgeIndexEntry>[];
    for (final document in documents) {
      if (document.status != KnowledgeApprovalStatus.approved) continue;
      final contentHash = KnowledgeCodec.contentHashForDocument(
        title: document.title,
        body: document.body,
      );
      if (contentHash != document.contentHash) {
        throw const KnowledgeIndexException(
          KnowledgeIndexErrorCode.contentHashMismatch,
        );
      }
      for (final chunk in codec.chunkDocument(document)) {
        entries.add(KnowledgeIndexEntry(document: document, chunk: chunk));
      }
    }
    entries.sort(_compareEntries);
    return KnowledgeIndex(entries: entries);
  }

  static int _compareEntries(
    KnowledgeIndexEntry left,
    KnowledgeIndexEntry right,
  ) {
    final documentOrder = left.document.id.compareTo(right.document.id);
    if (documentOrder != 0) return documentOrder;
    return left.chunk.index.compareTo(right.chunk.index);
  }

  static List<KnowledgeIndexEntry> _canonicalizeEntries(
    Iterable<KnowledgeIndexEntry> entries,
  ) {
    final approvedEntries = <KnowledgeIndexEntry>[];
    for (final entry in entries) {
      if (entry.document.status != KnowledgeApprovalStatus.approved) continue;
      _verifyEntry(entry);
      approvedEntries.add(entry);
    }
    approvedEntries.sort(_compareEntries);
    return List<KnowledgeIndexEntry>.unmodifiable(approvedEntries);
  }

  static void _verifyEntry(KnowledgeIndexEntry entry) {
    final documentHash = KnowledgeCodec.contentHashForDocument(
      title: entry.document.title,
      body: entry.document.body,
    );
    final chunkHash = KnowledgeCodec.contentHashForChunk(
      documentId: entry.chunk.documentId,
      index: entry.chunk.index,
      content: entry.chunk.content,
    );
    if (documentHash != entry.document.contentHash ||
        chunkHash != entry.chunk.contentHash) {
      throw const KnowledgeIndexException(
        KnowledgeIndexErrorCode.contentHashMismatch,
      );
    }
    final documentChunks = const KnowledgeCodec().chunkDocument(entry.document);
    if (entry.chunk.index >= documentChunks.length ||
        documentChunks[entry.chunk.index] != entry.chunk) {
      throw const KnowledgeIndexException(
        KnowledgeIndexErrorCode.chunkContentMismatch,
      );
    }
  }
}
