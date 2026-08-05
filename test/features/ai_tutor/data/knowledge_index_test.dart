import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_codec.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_document.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_index.dart';

import '../../../../tool/build_tutor_knowledge_index.dart';

const _codec = KnowledgeCodec();

void main() {
  group('KnowledgeIndex', () {
    test('indexes only approved documents with verified content hashes', () {
      final approved = _document(
        id: 'approved',
        locale: 'en',
        title: 'Approved title',
        body: 'Approved content.',
      );
      final rejected = _document(
        id: 'rejected',
        locale: 'en',
        title: 'Rejected title',
        body: 'Rejected content.',
        status: KnowledgeApprovalStatus.rejected,
      );

      final index = KnowledgeIndex.fromDocuments(<KnowledgeDocument>[
        rejected,
        approved,
      ]);

      expect(index.entries.map((entry) => entry.document.id), <String>[
        'approved',
      ]);
    });

    test(
      'rejects a document whose content does not match its content hash',
      () {
        final document = _document(
          id: 'mismatched',
          locale: 'en',
          title: 'Original title',
          body: 'Original content.',
        );
        final altered = KnowledgeDocument(
          schemaVersion: document.schemaVersion,
          id: document.id,
          locale: document.locale,
          skill: document.skill,
          difficulty: document.difficulty,
          license: document.license,
          version: document.version,
          status: document.status,
          title: document.title,
          body: 'Changed after approval.',
          contentHash: document.contentHash,
        );

        expect(
          () => KnowledgeIndex.fromDocuments(<KnowledgeDocument>[altered]),
          throwsA(
            isA<KnowledgeIndexException>().having(
              (error) => error.code,
              'code',
              KnowledgeIndexErrorCode.contentHashMismatch,
            ),
          ),
        );
      },
    );

    test('canonicalizes manually supplied entries by document and chunk', () {
      final alpha = _document(
        id: 'alpha',
        locale: 'en',
        title: 'Alpha title',
        body: 'Alpha content.',
      );
      final zulu = _document(
        id: 'zulu',
        locale: 'en',
        title: 'Zulu title',
        body: 'Zulu content.',
      );
      final generated = KnowledgeIndex.fromDocuments(<KnowledgeDocument>[
        zulu,
        alpha,
      ]);

      final index = KnowledgeIndex(entries: generated.entries.reversed);

      expect(index.entries.map((entry) => entry.document.id), <String>[
        'alpha',
        'zulu',
      ]);
    });

    test('rejects an unverified manually supplied document entry', () {
      final document = _document(
        id: 'manual-entry',
        locale: 'en',
        title: 'Original title',
        body: 'Original content.',
      );
      final altered = KnowledgeDocument(
        schemaVersion: document.schemaVersion,
        id: document.id,
        locale: document.locale,
        skill: document.skill,
        difficulty: document.difficulty,
        license: document.license,
        version: document.version,
        status: document.status,
        title: document.title,
        body: 'Changed after approval.',
        contentHash: document.contentHash,
      );
      final chunk = _codec.chunkDocument(document).single;

      expect(
        () => KnowledgeIndex(
          entries: <KnowledgeIndexEntry>[
            KnowledgeIndexEntry(document: altered, chunk: chunk),
          ],
        ),
        throwsA(
          isA<KnowledgeIndexException>().having(
            (error) => error.code,
            'code',
            KnowledgeIndexErrorCode.contentHashMismatch,
          ),
        ),
      );
    });

    test('rejects a chunk not derived from its document body', () {
      final document = _document(
        id: 'chunk-origin',
        locale: 'en',
        title: 'Chunk origin title',
        body: 'The approved document body.',
      );
      const injectedContent = 'An unrelated but hash-valid chunk.';
      final injectedChunk = KnowledgeChunk(
        documentId: document.id,
        index: 0,
        content: injectedContent,
        contentHash: KnowledgeCodec.contentHashForChunk(
          documentId: document.id,
          index: 0,
          content: injectedContent,
        ),
      );

      expect(
        () => KnowledgeIndex(
          entries: <KnowledgeIndexEntry>[
            KnowledgeIndexEntry(document: document, chunk: injectedChunk),
          ],
        ),
        throwsA(
          isA<KnowledgeIndexException>().having(
            (error) => error.code,
            'code',
            KnowledgeIndexErrorCode.chunkContentMismatch,
          ),
        ),
      );
    });
  });

  group('buildTutorKnowledgeIndex', () {
    late Directory temporaryDirectory;

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync(
        'strumsight-knowledge-index-test-',
      );
    });

    tearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });

    test('writes a bit-identical index when built twice', () {
      final contentRoot = Directory('${temporaryDirectory.path}/knowledge')
        ..createSync();
      final zDocument = _document(
        id: 'z-document',
        locale: 'en',
        title: 'Zebra title',
        body: 'Zebra content.',
      );
      final aDocument = _document(
        id: 'a-document',
        locale: 'hu',
        title: 'Alfa cím',
        body: 'Alfa tartalom.',
      );
      _writeDocument(contentRoot, zDocument);
      _writeDocument(contentRoot, aDocument);
      _writeManifest(contentRoot, <KnowledgeDocument>[zDocument, aDocument]);
      final output = File('${temporaryDirectory.path}/index.json');

      buildTutorKnowledgeIndex(contentRoot: contentRoot, outputFile: output);
      final first = output.readAsBytesSync();
      buildTutorKnowledgeIndex(contentRoot: contentRoot, outputFile: output);
      final second = output.readAsBytesSync();

      expect(first, equals(second));
      final root = jsonDecode(utf8.decode(first)) as Map<String, dynamic>;
      expect(
        (root['entries'] as List<Object?>).cast<Map<String, Object?>>().map(
          (entry) => entry['documentId'],
        ),
        <Object?>['a-document', 'z-document'],
      );
    });

    test('emits only documents sealed by the committed manifest', () {
      final contentRoot = Directory('${temporaryDirectory.path}/knowledge')
        ..createSync();
      final indexed = _document(
        id: 'indexed-document',
        locale: 'en',
        title: 'Indexed title',
        body: 'Indexed content.',
      );
      final unlisted = _document(
        id: 'unlisted-document',
        locale: 'en',
        title: 'Unlisted title',
        body: 'Unlisted content.',
      );
      _writeDocument(contentRoot, indexed);
      _writeDocument(contentRoot, unlisted);
      _writeManifest(contentRoot, <KnowledgeDocument>[indexed]);
      final output = File('${temporaryDirectory.path}/index.json');

      buildTutorKnowledgeIndex(contentRoot: contentRoot, outputFile: output);

      final root =
          jsonDecode(output.readAsStringSync()) as Map<String, dynamic>;
      expect(
        (root['entries'] as List<Object?>).cast<Map<String, Object?>>().map(
          (entry) => entry['documentId'],
        ),
        <Object?>['indexed-document'],
      );
    });
  });
}

KnowledgeDocument _document({
  required String id,
  required String locale,
  required String title,
  required String body,
  KnowledgeSkill skill = KnowledgeSkill.rhythm,
  KnowledgeDifficulty difficulty = KnowledgeDifficulty.beginner,
  KnowledgeApprovalStatus status = KnowledgeApprovalStatus.approved,
}) => KnowledgeDocument(
  schemaVersion: KnowledgeDocument.currentSchemaVersion,
  id: id,
  locale: locale,
  skill: skill,
  difficulty: difficulty,
  license: 'CC0-1.0',
  version: 1,
  status: status,
  title: title,
  body: body,
  contentHash: KnowledgeCodec.contentHashForDocument(title: title, body: body),
);

void _writeDocument(Directory root, KnowledgeDocument document) {
  final file = File('${root.path}/${document.locale}/${document.id}.json');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(_codec.encodeDocument(document));
}

void _writeManifest(Directory root, List<KnowledgeDocument> documents) {
  final manifest = <String, Object?>{
    'schemaVersion': KnowledgeCodec.manifestSchemaVersion,
    'documents': <Object?>[
      for (final document in documents)
        <String, Object?>{
          'id': document.id,
          'locale': document.locale,
          'skill': document.skill.name,
          'difficulty': document.difficulty.name,
          'license': document.license,
          'version': document.version,
          'contentHash': document.contentHash,
          'sourcePath': '${document.locale}/${document.id}.json',
          'chunks': <Object?>[
            for (final chunk in _codec.chunkDocument(document))
              <String, Object?>{
                'id': chunk.id,
                'index': chunk.index,
                'contentHash': chunk.contentHash,
              },
          ],
        },
    ],
  };
  File('${root.path}/manifest.json').writeAsStringSync(jsonEncode(manifest));
}
