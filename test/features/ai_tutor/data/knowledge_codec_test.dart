import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_codec.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_document.dart';

const _codec = KnowledgeCodec();

void main() {
  group('KnowledgeCodec', () {
    test('round-trips a document and its deterministic chunks', () {
      final document = _document();

      final decoded = _codec.decodeDocument(_codec.encodeDocument(document));
      final chunks = _codec.chunkDocument(decoded);

      expect(decoded, equals(document));
      expect(
        chunks,
        equals(<KnowledgeChunk>[
          KnowledgeChunk(
            documentId: document.id,
            index: 0,
            content: 'Count four even beats before playing.',
            contentHash: KnowledgeCodec.contentHashForChunk(
              documentId: document.id,
              index: 0,
              content: 'Count four even beats before playing.',
            ),
          ),
          KnowledgeChunk(
            documentId: document.id,
            index: 1,
            content: 'Keep the motion small and relaxed.',
            contentHash: KnowledgeCodec.contentHashForChunk(
              documentId: document.id,
              index: 1,
              content: 'Keep the motion small and relaxed.',
            ),
          ),
        ]),
      );
    });

    test('encodes equal documents as byte-identical canonical JSON', () {
      final document = _document();

      final first = _codec.encodeDocument(document);
      final second = _codec.encodeDocument(document);

      expect(first, equals(second));
    });

    test('rejects an unknown approval status with a stable error code', () {
      final json = _documentMap();
      json['status'] = 'unreviewed';

      expect(
        () => _codec.decodeDocument(utf8.encode(jsonEncode(json))),
        throwsA(
          isA<KnowledgeCodecException>().having(
            (error) => error.code,
            'code',
            KnowledgeCodecErrorCode.statusUnknown,
          ),
        ),
      );
    });

    test('rejects an invalid content hash with a stable error code', () {
      final json = _documentMap();
      json['contentHash'] = 'not-a-sha256';

      expect(
        () => _codec.decodeDocument(utf8.encode(jsonEncode(json))),
        throwsA(
          isA<KnowledgeCodecException>().having(
            (error) => error.code,
            'code',
            KnowledgeCodecErrorCode.fieldInvalid,
          ),
        ),
      );
    });
  });
}

KnowledgeDocument _document() {
  const title = 'Keep a steady pulse';
  const body =
      'Count four even beats before playing.\n\nKeep the motion small and relaxed.';
  return KnowledgeDocument(
    schemaVersion: KnowledgeDocument.currentSchemaVersion,
    id: 'rhythm-steady-pulse-en',
    locale: 'en',
    skill: KnowledgeSkill.rhythm,
    difficulty: KnowledgeDifficulty.beginner,
    license: 'CC0-1.0',
    version: 1,
    status: KnowledgeApprovalStatus.approved,
    title: title,
    body: body,
    contentHash: KnowledgeCodec.contentHashForDocument(
      title: title,
      body: body,
    ),
  );
}

Map<String, Object?> _documentMap() => Map<String, Object?>.from(
  jsonDecode(utf8.decode(_codec.encodeDocument(_document())))
      as Map<String, dynamic>,
);
